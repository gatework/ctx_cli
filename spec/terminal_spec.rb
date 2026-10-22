# frozen_string_literal: true

RSpec.describe "Terminal interaction" do
  def terminal_stream(text = "")
    StringIO.new(+text).tap { |stream| stream.define_singleton_method(:tty?) { true } }
  end

  it "does not consume piped confirmation" do
    input, output = StringIO.new("APPLY host hash\n"), terminal_stream
    terminal = CtxCli::Terminal.new(input: input, out: output)
    expect { terminal.confirm(token: "APPLY host hash", prompt: "confirm") }.to raise_error(ArgumentError)
    expect(input.pos).to eq(0)
    expect(output.string).to eq("")
  end

  it "requires the entire token and uses explicit line separators" do
    input, output = terminal_stream("APPLY host hash wrong\nAPPLY host hash item\n"), terminal_stream
    terminal = CtxCli::Terminal.new(input: input, out: output)
    original = $/
    begin
      $/ = "!"
      expect(terminal.confirm(token: "APPLY host hash item", prompt: "confirm")).to be(false)
      expect(terminal.confirm(token: "APPLY host hash item", prompt: "confirm")).to be(true)
    ensure
      $/ = original
    end
    expect(input).not_to be_closed
  end
end
