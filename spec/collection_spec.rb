# frozen_string_literal: true

RSpec.describe CtxCli::Collection do
  def entrypoint(adapter:, flags:, out:, error:)
    options = double("options", informational?: false, validate_interaction!: nil, load_environment: nil,
      missing?: false, load: nil, config: "audit.yml", flags: flags)
    progress = double("progress", notice: nil, output_error: false)
    described_class.new(adapter: adapter, options: ->(_) { options }, progress: ->(_) { progress },
      batch: Object, label: "Audit", report_error: IOError, failure_code: ->(_) { :failed },
      out: out, error: error, input: StringIO.new)
  end

  it "exports inventory without preparing credentials, creating reports or starting a batch" do
    devices = [ { "host" => "192.0.2.10", "name" => "edge" } ]
    adapter = double("adapter", inventory: [ devices, 1 ])
    output, errors = StringIO.new, StringIO.new
    entry = entrypoint(adapter: adapter, flags: { inventory_only: true, json: true }, out: output, error: errors)
    expect(entry.run([])).to eq(0)
    expect(JSON.parse(output.string)).to eq(devices)
    expect(errors.string).to eq("")
    expect(output).not_to be_closed
  end

  it "fails preflight before a report or batch can start" do
    adapter = double("adapter", inventory: [ [ { "host" => "192.0.2.10" } ], 1 ])
    allow(adapter).to receive(:prepare).and_raise(ArgumentError, "missing username")
    output, errors = StringIO.new, StringIO.new
    entry = entrypoint(adapter: adapter, flags: {}, out: output, error: errors)
    expect(entry.run([])).to eq(2)
    expect(output.string).to eq("")
    expect(errors.string).to include("missing username")
  end
end
