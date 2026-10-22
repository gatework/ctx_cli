# frozen_string_literal: true

require "optparse"
require_relative "output"

module CtxCli
  # 终端采集入口的固定顺序；领域适配器拥有清单、预检、调度及采集策略。
  class Collection
    def initialize(adapter:, options:, progress:, batch:, label:, report_error:, failure_code:,
                   out: $stdout, error: $stderr, input: $stdin)
      @adapter, @options_factory, @progress_factory, @batch_class = adapter, options, progress, batch
      @label, @report_error, @failure_code = label, report_error, failure_code
      @out, @error, @input = out, error, input
      @output = Output.new(out: out, error: error)
    end

    # 先预检全部输入和凭据，再创建报告和连接；失败分类不打印原始异常正文。
    def run(argv)
      # 每次运行独立持有批次状态；预检失败不能改写上一次报告。
      @options, @store, @progress, @devices, @batch = nil, nil, nil, [], nil
      @options = @options_factory.call(argv)
      return 0 if @options.informational?
      @options.validate_interaction!(input: @input, error: @error)
      @options.load_environment
      if @options.flags[:init]
        @options.initialize_files
        return 0
      end
      return 0 if @options.missing?(input: @input, error: @error)
      @options.load
      @progress = @progress_factory.call(@options)
      @progress.notice("配置：#{@options.config}")
      return output(@options.public_values.merge("sources" => @options.sources)) if @options.flags[:show_config]
      @devices, @inventory_total = @adapter.inventory(@options, progress: @progress)
      devices = @devices
      return output(devices) if @options.flags[:inventory_only]
      if devices.empty?
        @progress.notice("没有匹配设备，未建立连接")
        @output.json({ status: :no_devices, total: 0 }, pretty: false) if @options.flags[:json]
        return 1
      end
      context = @adapter.prepare(devices, @options)
      @store = @adapter.report(@options)
      @batch = @batch_class.new(report: @store, progress: @progress, requested: devices)
      outcome = @batch.run(present: ->(summary) { @output.json(summary) if @options.flags[:json] }) do
        @progress.plan(devices: devices, total: @inventory_total, parallel: @options.values.fetch("parallel"), label: "#{@label} 只读采集")
        @progress.with_updates do
          @adapter.execute(devices, @options) do |device|
            @batch.collect(device) { @adapter.collect(device, @options, context: context, progress: @progress) }
          end
        end
        @adapter.after_collect(@store, @options)
      end
      completion(outcome)
    rescue Interrupt
      diagnostic "采集已取消，已保存的设备报告保留；未保存结果见报告状态"
      130
    rescue SystemCallError, IOError => error
      diagnostic "#{@label} 参数或报告错误：#{report_diagnostic(error)}"
      2
    rescue OptionParser::ParseError, ArgumentError, LoadError => error
      diagnostic "#{@label} 参数、依赖或报告错误：#{error.message}；使用 --help 查看参数"
      2
    rescue StandardError => error
      diagnostic "#{@label} 清单或执行失败：#{@failure_code.call(error)}（#{error.class.name}）"
      2
    end

    def inspect = "#<#{self.class.name}>"
    alias_method :to_s, :inspect
    def pretty_print(printer) = printer.text(inspect)

    private

    # Runner 决定批次结论；CLI 仅呈现安全诊断并映射退出码。
    def completion(outcome)
      if outcome.finalization_error
        diagnostic "#{@label} 摘要报告错误：#{outcome.finalization_error}"
      end
      if outcome.recovery_failed
        diagnostic "摘要恢复未确认；请依据退出码及报告目录检查，不能将旧摘要视为本次成功。"
      end
      if outcome.status == :interrupted
        diagnostic "采集已取消，已保存的设备报告保留；未保存结果见报告状态"
      elsif (failure = outcome.failure)
        if failure[:kind] == :report
          diagnostic "#{@label} 参数或报告错误：#{failure[:detail]}"
        else
          diagnostic "#{@label} 清单或执行失败：#{failure[:error_type]}；已采集结果见批次报告"
        end
      end
      { complete: 0, incomplete: 1, failed: 2, interrupted: 130 }.fetch(outcome.status)
    end

    # 错误提示失败不能覆盖取消或执行退出码；已失效的进度流不再重试。
    def diagnostic(message)
      @output.diagnostic(message) unless @progress&.output_error
    end

    # 自有发布错误消息不含正文；外部文件异常只显示类型，不打印 message/cause。
    def report_diagnostic(error)
      error.instance_of?(@report_error) ? error.message : error.class.name
    end

    # 预览默认显示逐设备身份；公开配置由显式开关展示。
    def output(value)
      if @options.flags[:json] || value.is_a?(Hash)
        @output.json(value)
      else
        value.each { |device| @out.puts "#{device.fetch('host')}\t#{device.fetch('name')}\t#{device['model']}" }
        @out.puts "设备：#{value.size} 台；未建立设备连接"
      end
      value.is_a?(Array) && value.empty? ? 1 : 0
    end
  end
end
