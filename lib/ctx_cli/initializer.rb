# frozen_string_literal: true

require "fileutils"
require "tempfile"

module CtxCli
  # 只发布已经过宿主校验的模板，不收集凭据、不覆盖已有目录项。
  class Initializer
    def initialize(prefix: ".ctx-cli-init-")
      @prefix = prefix
    end

    # 符号链接和目录不算可保留配置；用 lstat 同时拒绝悬空链接。
    def existing?(path)
      stat = File.lstat(path)
      raise ArgumentError, "config path must be a regular file" unless stat.file?
      true
    rescue Errno::ENOENT
      false
    end

    # 文件先完整同步，排他链接后再同步目录；失败不返回已确认状态。
    def create(path:, contents:)
      raise ArgumentError, "config path must be a nonempty String" unless path.is_a?(String) && !path.empty?
      return :exists if existing?(path)
      prepare_directory(File.dirname(File.expand_path(path)))
      directory = File.realpath(File.dirname(File.expand_path(path)))
      destination = File.join(directory, File.basename(path))
      file = parent = primary = nil
      begin
        Thread.handle_interrupt(Exception => :never) { file = Tempfile.new([ @prefix, ".tmp" ], directory) }
        file.binmode
        file.chmod(0o600)
        file.write(contents)
        file.flush
        file.fsync
        begin
          File.link(file.path, destination)
        rescue Errno::EEXIST
          return :exists if existing?(destination)
          raise
        end
        Thread.handle_interrupt(Exception => :never) { parent = File.open(directory, File::RDONLY | File::NOFOLLOW) }
        parent.fsync
        :created
      rescue Exception => failure # rubocop:disable Lint/RescueException -- 清理不能覆盖取消或发布故障。
        primary = failure
        raise
      ensure
        close_files(file, parent, primary)
      end
    end

    private

    # 先确认新目录在各父级的名字已同步，再发布其中的配置文件。
    def prepare_directory(path)
      missing, parent = [], path
      until File.directory?(parent)
        missing << parent
        parent = File.dirname(parent)
      end
      FileUtils.mkdir_p(path, mode: 0o700)
      missing.reverse_each do |created|
        File.open(File.realpath(File.dirname(created)), File::RDONLY | File::NOFOLLOW) { |directory| directory.fsync }
      end
    end

    # 全部句柄都尝试关闭，保留原始故障；不把清理失败变为成功。
    def close_files(file, parent, primary)
      Thread.handle_interrupt(Exception => :never) do
        error = nil
        [ -> { parent&.close }, -> { file&.close! } ].each do |close|
          begin
            close.call
          rescue Exception => failure # rubocop:disable Lint/RescueException -- 两个资源均尝试关闭。
            error ||= failure
          end
        end
        raise error if error && !primary
      end
    end
  end
end
