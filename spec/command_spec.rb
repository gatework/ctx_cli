# frozen_string_literal: true

RSpec.describe "Command boundaries" do
  it "dispatches only the chosen command and rejects arguments after global help" do
    output, errors, calls = StringIO.new, StringIO.new, []
    app = CtxCli::Application.new(name: "sample", version: "1.2", usage: "usage", out: output, error: errors,
      commands: { "read" => ->(args) { calls << args; 7 } })
    expect(app.run([ "--help" ])).to eq(0)
    expect(app.run([ "--version" ])).to eq(0)
    expect(calls).to be_empty
    expect(app.run([ "--help", "extra" ])).to eq(2)
    argv = [ "read", "file" ]
    expect(app.run(argv)).to eq(7)
    expect(calls).to eq([ [ "file" ] ])
    expect(argv).to eq([ "read", "file" ])
  end

  it "copies defaults and formats informational output without executing or reading input" do
    defaults = { dimensions: [], complete: false }
    output = StringIO.new
    command = CtxCli::Command.new(banner: "usage", defaults: defaults, out: output) do |parser, values|
      parser.on("--dimension NAME") { |name| values[:dimensions] << name }
      CtxCli::Options.information(parser, values)
    end
    command.parse([ "--dimension", "configuration", "--help" ])
    expect(command.informational?(examples: "example")).to be(true)
    expect(output.string).to include("usage", "--dimension")
    expect(defaults).to eq(dimensions: [], complete: false)
    expect { command.parse([ "unexpected" ]) }.to raise_error(ArgumentError)
    command.parse([])
    expect(command.values).to eq(defaults)
  end

  it "retains false flags and rejects empty list elements" do
    command = CtxCli::Command.new(banner: "usage") do |parser, values|
      CtxCli::Options.initialization(parser, values)
      CtxCli::Options.output(parser, values, quiet: :no_progress)
    end
    command.parse(%w[--interactive --non-interactive --quiet --json])
    expect(command.values).to include(interactive: false, no_progress: true, json: true)
    expect(CtxCli::Options.list(" a,b ")).to eq(%w[a b])
    expect { CtxCli::Options.list("a,") }.to raise_error(ArgumentError)
  end

  it "does not expose option values through default inspection" do
    command = CtxCli::Command.new(banner: "usage", defaults: { password: "SYNTHETIC-SECRET" })
    command.parse([])
    expect(command.inspect + command.to_s).not_to include("SYNTHETIC-SECRET")
  end

  it "does not close borrowed input and separates explicit JSON from safe diagnostics" do
    source, out, errors = StringIO.new("evidence"), StringIO.new, StringIO.new
    expect(CtxCli::Input.read(input: source)).to eq("evidence")
    expect(source).not_to be_closed
    output = CtxCli::Output.new(out: out, error: errors)
    output.json({ status: "partial" })
    output.diagnostic("failed", exception: ArgumentError.new("SYNTHETIC-SECRET"))
    expect(JSON.parse(out.string)).to eq("status" => "partial")
    expect(errors.string).to include("ArgumentError")
    expect(errors.string).not_to include("SYNTHETIC-SECRET")
    out.close
    expect { output.json({}) }.to raise_error(IOError)
    errors.close
    expect { output.diagnostic("failed") }.not_to raise_error
  end
end
