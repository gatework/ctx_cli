# frozen_string_literal: true

require "yaml"
require_relative "input"

module CtxCli
  # 宿主配置发现；加载文件不读取配置或建立设备连接。
  class Configuration
    # 仅用于本类构造的公开配置诊断，不携带文件正文。
    class Error < ArgumentError; end

    MAX_DEPTH = 128
    MAX_NODES = 100_000
    attr_reader :data, :specific, :process_environment, :file_environment, :environment,
                :config_files, :environment_files, :sources

    def initialize(name:, env: ENV, script: $PROGRAM_NAME, cwd: Dir.pwd, home: Dir.home,
                   directories: nil, config: nil, env_file: nil, config_env: nil,
                   path_fields: [], env_path_keys: [], path_literals: {},
                   namespace: name, names: [ name.to_s ], common_keys: [])
      @name = name.to_s.dup.freeze
      @namespace = namespace.to_s.dup.freeze
      @names = self.class.freeze_tree(self.class.copy(names))
      @common_keys = self.class.freeze_tree(self.class.copy(common_keys))
      raise ArgumentError, "unsupported configuration name: #{@name}" unless @names.include?(@name)

      @cwd = File.expand_path(cwd)
      @home = File.expand_path(home)
      @config_env = (config_env || "#{@name.upcase}_CONFIG").to_s.dup.freeze
      @env_path_keys = (env_path_keys.map { |key| key.to_s.dup.freeze } + [ @config_env ]).uniq.freeze
      @path_literals = self.class.freeze_tree(self.class.copy(path_literals.transform_keys(&:to_s)))
      @process_environment = self.class.copy(env.to_h)
      resolve_environment_paths!(@process_environment, @cwd)
      self.class.freeze_tree(@process_environment)
      @user_directory = File.join(user_config_home, @namespace)
      @directories = (directories || [ "/etc/#{@namespace}", "/usr/local/etc/#{@namespace}", @user_directory,
                                      File.dirname(File.expand_path(script, @cwd)), @cwd ]).map do |path|
        File.expand_path(path, @cwd)
      end.uniq
      @explicit_config = absolute(config, @cwd)
      @explicit_env_file = absolute(env_file, @cwd)
      @path_fields = path_fields.map { |path| path.to_s.split(".") }
      @data = @specific = @file_environment = @environment = {}.freeze
      @config_files = @environment_files = [].freeze
      @sources = { "configuration_files" => @config_files, "environment_files" => @environment_files, "fields" => {}.freeze }.freeze
    end

    # 环境文件只形成私有快照，不修改 ENV，不读取 YAML。
    def load_environment(allow_missing: false)
      return self if @environment_loaded

      files = candidates(".env", @explicit_env_file)
      values = {}
      loaded = []
      files.each do |path|
        next unless readable_file?(path, explicit: path == @explicit_env_file, allow_missing: allow_missing)

        parsed = parse_environment(path, values.merge(@process_environment))
        resolve_environment_paths!(parsed, File.dirname(path))
        values.merge!(parsed)
        loaded << path
      end
      @file_environment = self.class.freeze_tree(values)
      @environment = self.class.freeze_tree(values.merge(self.class.copy(@process_environment)))
      @environment_files = self.class.freeze_tree(loaded)
      # 空的选择变量视为缺失，包括进程中显式的空值。
      selector = present(@process_environment[@config_env]) || present(values[@config_env])
      @selected_config = @explicit_config || absolute(selector, @cwd)
      @environment_loaded = true
      update_sources({})
      self
    end

    # 每批固定一份快照；重复调用不重新读取文件。
    def load(allow_missing: false)
      return self if @loaded

      load_environment(allow_missing: allow_missing)
      merged = {}
      specific = {}
      fields = {}
      loaded = []
      applicable = false
      paths = @directories.flat_map { |directory| [ File.join(directory, "#{@namespace}.yml"), File.join(directory, "#{@name}.yml") ] }
      paths = final_candidates(paths, @selected_config)
      paths.each do |path|
        next unless readable_file?(path, explicit: path == @selected_config, allow_missing: allow_missing)

        document = read_yaml(path)
        if @namespace != @name && File.basename(path) == "#{@namespace}.yml"
          common, native, native_present = shared_sections(document, path)
          merged = merge_layer(merged, common, path, fields)
          applicable ||= native_present
        else
          native = document
          validate_string_keys!(native, path)
          applicable = true
        end
        merged = merge_layer(merged, native, path, fields)
        specific = self.class.merge(specific, resolve_paths(native, path))
        loaded << path
      end
      @data = self.class.freeze_tree(merged)
      @specific = self.class.freeze_tree(specific)
      @config_files = self.class.freeze_tree(loaded)
      update_sources(fields)
      @applicable = applicable
      @loaded = true
      self
    end

    def config
      @selected_config || @explicit_config || @config_files.last || init_config
    end

    def env_file
      @explicit_env_file || @environment_files.last || init_env_file
    end

    def init_config
      @selected_config || @explicit_config || File.join(@user_directory, "#{@name}.yml")
    end

    def init_env_file
      @explicit_env_file || File.join(@user_directory, ".env")
    end

    def missing?
      !@applicable
    end

    # 序列化规则与目标文件的发现规则一致。
    def self.dump(document, name:, path:, namespace: name)
      YAML.dump(File.basename(path) == "#{namespace}.yml" && namespace.to_s != name.to_s ? { name.to_s => document } : document)
    end

    # 默认展示仅包含类型，公开来源通过 sources 显式读取。
    def inspect = "#<#{self.class.name}>"
    alias_method :to_s, :inspect
    def pretty_print(printer) = printer.text(inspect)

    # 每层只复制一次，再合并拥有的映射；数组、false、nil 按值替换。
    def self.merge(*hashes)
      hashes.reduce({}) do |result, hash|
        raise ArgumentError, "configuration layers must be mappings" unless hash.is_a?(Hash)
        pending = [ [ result, copy(hash) ] ]
        until pending.empty?
          target, source = pending.pop
          source.each do |key, value|
            if target[key].is_a?(Hash) && value.is_a?(Hash)
              pending << [ target[key], value ]
            else
              target[key] = value
            end
          end
        end
        result
      end
    end

    # 只复制普通数据；循环或不透明对象不能进入快照并冻结调用方资源。
    def self.copy(value) = copy_value(value, {}.compare_by_identity, 0, [ MAX_NODES ])

    def self.copy_value(value, active, depth, budget)
      raise ArgumentError, "configuration nesting exceeds budget" if depth > MAX_DEPTH
      budget[0] -= 1
      raise ArgumentError, "configuration node budget exceeded" if budget[0].negative?
      case value
      when Hash, Array
        raise ArgumentError, "cyclic configuration value" if active.key?(value)
        active[value] = true
        begin
          if value.is_a?(Hash)
            value.to_h { |key, entry| [ copy_value(key, active, depth + 1, budget), copy_value(entry, active, depth + 1, budget) ] }
          else
            value.map { |entry| copy_value(entry, active, depth + 1, budget) }
          end
        ensure
          active.delete(value)
        end
      when String then String.new(value)
      when Integer, Float, Symbol, NilClass, TrueClass, FalseClass then value
      else raise ArgumentError, "configuration accepts plain data only"
      end
    end
    private_class_method :copy_value

    def self.freeze_tree(value)
      case value
      when Hash then value.each { |key, entry| freeze_tree(key); freeze_tree(entry) }
      when Array then value.each { |entry| freeze_tree(entry) }
      end
      value.freeze
    end

    private

    def present(value)
      value unless value.nil? || value.to_s.strip.empty?
    end

    def absolute(path, directory)
      File.expand_path(path.to_s, directory) if present(path)
    end

    def user_config_home
      absolute(present(@process_environment["XDG_CONFIG_HOME"]), @cwd) || File.join(@home, ".config")
    end

    def candidates(filename, explicit)
      final_candidates(@directories.map { |directory| File.join(directory, filename) }, explicit)
    end

    def final_candidates(paths, explicit)
      paths = paths.reject { |path| path == explicit } + [ explicit ] if explicit
      paths.uniq
    end

    def readable_file?(path, explicit:, allow_missing:)
      unless File.exist?(path)
        raise Error, "configuration file does not exist: #{path}" if explicit && !allow_missing

        return false
      end
      return true if File.file?(path) && File.readable?(path)

      raise ArgumentError, "configuration path is not a readable regular file: #{path}"
    end

    def read_yaml(path)
      contents = Input.read(path: path)
      validate_yaml_structure!(contents, path)
      document = YAML.safe_load(contents, permitted_classes: [], permitted_symbols: [], aliases: false)
      document = {} if document.nil?
      raise ArgumentError, "configuration must contain a mapping: #{path}" unless document.is_a?(Hash)

      document
    rescue Psych::Exception, SystemCallError, IOError => error
      raise ArgumentError, "cannot read configuration file: #{path} (#{error.class})", cause: nil
    end

    # 覆盖只能来自明确文件层；同文件不能隐藏重复键
    # 或在领域校验前静默丢弃后续文档。
    def validate_yaml_structure!(contents, path)
      stream = YAML.parse_stream(contents)
      raise ArgumentError, "configuration must contain a single YAML document: #{path}" if stream.children.size > 1

      pending = [ [ stream, 0 ] ]
      remaining = MAX_NODES
      until pending.empty?
        node, depth = pending.pop
        raise ArgumentError, "configuration nesting exceeds budget" if depth > MAX_DEPTH
        remaining -= 1
        raise ArgumentError, "configuration node budget exceeded" if remaining.negative?
        node.children&.reverse_each { |child| pending << [ child, depth + 1 ] }
        next unless node.is_a?(Psych::Nodes::Mapping)

        keys = {}
        node.children.each_slice(2) do |key, _|
          next unless key.is_a?(Psych::Nodes::Scalar)
          if keys.key?(key.value)
            raise ArgumentError, "duplicate configuration key at line #{key.start_line + 1}: #{path}"
          end

          keys[key.value] = true
        end
      end
    end

    def validate_string_keys!(value, path)
      case value
      when Hash
        raise ArgumentError, "configuration keys must be strings: #{path}" unless value.keys.all?(String)

        value.each_value { |entry| validate_string_keys!(entry, path) }
      when Array
        value.each { |entry| validate_string_keys!(entry, path) }
      end
    end

    def shared_sections(document, path)
      unknown = document.keys - [ "common", *@names ]
      raise ArgumentError, "unknown shared configuration namespaces in #{path}: #{unknown.join(", ")}" unless unknown.empty?

      common = document.fetch("common", {})
      native = document.fetch(@name, {})
      unless common.is_a?(Hash) && native.is_a?(Hash)
        raise ArgumentError, "common and #{@name} configuration must contain mappings: #{path}"
      end
      unknown_common = common.keys - @common_keys
      unless unknown_common.empty?
        raise ArgumentError, "unsupported common configuration fields in #{path}: #{unknown_common.join(", ")}"
      end
      validate_string_keys!(common, path)
      validate_string_keys!(native, path)
      [ common, native, document.key?(@name) ]
    end

    def resolve_paths(document, path)
      result = self.class.copy(document)
      @path_fields.each { |segments| resolve_path!(result, segments, File.dirname(path), segments.join(".")) }
      result
    end

    def resolve_path!(value, segments, directory, field)
      return unless value.is_a?(Hash) && !segments.empty?

      key, *rest = segments
      keys = key == "*" ? value.keys : [ key ]
      keys.each do |entry|
        next unless value.key?(entry)

        if rest.empty?
          value[entry] = declared_path(value[entry], directory, field) if value[entry].is_a?(String) && !value[entry].empty?
        else
          resolve_path!(value[entry], rest, directory, field)
        end
      end
    end

    # 路径也可能是远程归档 URI，不能无条件转成本机路径。
    def declared_path(value, directory, field)
      raise ArgumentError if value.to_s.include?("\0")

      return value if @path_literals.fetch(field, []).include?(value)

      value.to_s.match?(%r{\A[A-Za-z][A-Za-z0-9+.-]*://}) ? value : absolute(value, directory)
    rescue ArgumentError
      raise ArgumentError, "invalid path #{field}", cause: nil
    end

    def resolve_environment_paths!(values, directory)
      @env_path_keys.each do |key|
        values[key] = declared_path(values[key], directory, key) if present(values[key])
      end
    end

    def merge_layer(previous, document, path, fields)
      resolved = resolve_paths(document, path)
      record_fields(resolved, path, fields, previous: previous)
      self.class.merge(previous, resolved)
    end

    # 用 JSON Pointer 区分字面键与层级，只移除被替换映射的真正后代来源。
    def record_fields(document, source, fields, prefix = "", previous: {})
      document.each do |key, value|
        name = "#{prefix}/#{key.gsub("~", "~0").gsub("/", "~1")}"
        before = previous.is_a?(Hash) ? previous[key] : nil
        next if value.is_a?(Hash) && value.empty? && before.is_a?(Hash) && !before.empty?

        if value.is_a?(Hash) && !value.empty?
          fields.delete(name)
          record_fields(value, source, fields, name, previous: before)
        else
          # 只有旧映射被整体替换才需要删除后代；新增/覆盖叶子直接赋值。
          if before.is_a?(Hash) && !before.empty?
            descendant_prefix = "#{name}/"
            fields.delete_if { |field, _| field.start_with?(descendant_prefix) }
          end
          fields[name] = source
        end
      end
    end

    def update_sources(fields)
      @sources = self.class.freeze_tree({ "configuration_files" => @config_files,
                                          "environment_files" => @environment_files, "fields" => fields })
    end

    # 复用 dotenv 语法，但替换只读取本次快照：
    # 不能使用默认的进程 ENV 读取或命令替换。
    def parse_environment(path, inherited)
      require "dotenv"
      process = @process_environment
      variable_pattern = Dotenv::Substitutions::Variable.singleton_class.const_get(:VARIABLE)
      parser_class = Class.new(Dotenv::Parser) do
        define_singleton_method(:substitutions) do
          [ lambda do |value, local|
            raise ArgumentError, "command substitution is unsupported" if value.include?("$(")

            value.gsub(variable_pattern) do |variable|
              match = Regexp.last_match
              if match[1] == "\\"
                variable[1..]
              elsif match[3]
                process.fetch(match[3]) { local.fetch(match[3]) { inherited.fetch(match[3], "") } }
              else
                variable
              end
            end
          end ]
        end
        define_method(:expand_newlines) do |value|
          if (@hash["DOTENV_LINEBREAK_MODE"] || inherited["DOTENV_LINEBREAK_MODE"]) == "legacy"
            value.gsub('\\n', "\n").gsub('\\r', "\r")
          else
            value.gsub('\\n', "\\\\\\n").gsub('\\r', "\\\\\\r")
          end
        end
        private :expand_newlines
      end
      contents = Input.read(path: path)
      remainder = contents.gsub(Dotenv::Parser::LINE, "")
      unless remainder.lines("\n").all? { |line| line.strip.empty? || line.lstrip.start_with?("#") }
        raise ArgumentError, "invalid environment syntax"
      end
      parser_class.call(contents, overwrite: true)
    rescue Dotenv::FormatError, ArgumentError, SystemCallError, IOError => error
      raise ArgumentError, "cannot read environment file: #{path} (#{error.class})", cause: nil
    end
  end
end
