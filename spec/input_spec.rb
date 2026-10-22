# frozen_string_literal: true

RSpec.describe CtxCli::Input do
  it "reads an empty file as empty text" do
    Dir.mktmpdir do |root|
      path = File.join(root, "empty")
      File.write(path, "")
      expect(described_class.read(path: path)).to eq("")
    end
  end

  it "bounds byte reads without closing a borrowed stream" do
    input = StringIO.new("中文")
    expect { described_class.read(input: input, max_bytes: 5) }.to raise_error(ArgumentError, /budget/)
    expect(input).not_to be_closed
    input.rewind
    expect(described_class.read(input: input, max_bytes: 6)).to eq("中文")
  end
end
