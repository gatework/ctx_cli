# frozen_string_literal: true

RSpec.describe "offline review boundaries" do
  it "bounds total source bytes and file count before publication" do
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "devices"))
      %w[a b].each { |name| File.write(File.join(root, "devices", "#{name}.json"), "{}") }
      command = CtxCli::Command.new(banner: "review", defaults: { batch: root })
      [ { max_total_bytes: 3 }, { max_files: 1 } ].each do |limits|
        adapter = double("adapter")
        review = CtxCli::Review.new(command: command, directory: "devices", adapter: adapter,
          out: StringIO.new, error: StringIO.new, **limits)
        expect(review.run([])).to eq(2)
      end
      adapter = double("adapter", prepare: nil, publish: "done")
      review = CtxCli::Review.new(command: command, directory: "devices", adapter: adapter,
        out: StringIO.new, error: StringIO.new, max_files: 2, max_total_bytes: 4)
      expect(review.run([])).to eq(0)
    end
  end

  it "treats brackets in the batch directory literally" do
    Dir.mktmpdir do |root|
      batch = File.join(root, "[batch]")
      FileUtils.mkdir_p(File.join(batch, "devices"))
      File.write(File.join(batch, "devices", "a.json"), "{}")
      command = CtxCli::Command.new(banner: "review", defaults: { batch: batch })
      adapter = double("adapter")
      expect(adapter).to receive(:prepare).with([ [ File.join(batch, "devices", "a.json"), "{}", {} ] ], { batch: batch }).and_return(:ready)
      expect(adapter).to receive(:publish).and_return("done")
      entry = CtxCli::Review.new(command: command, directory: "devices", adapter: adapter, out: StringIO.new, error: StringIO.new)
      expect(entry.run([])).to eq(0)
    end
  end

  it "shows help without loading sources or invoking the adapter" do
    out = StringIO.new
    command = CtxCli::Command.new(banner: "review", out: out) do |parser, values|
      parser.on("--help") { values[:help] = true }
    end
    entry = CtxCli::Review.new(command: command, directory: "devices", adapter: Object.new, out: out)
    expect(entry.run([ "--help" ])).to eq(0)
    expect(out.string).to include("review")
  end

  it "validates every input before allowing publication and redacts malformed input" do
    Dir.mktmpdir do |root|
      Dir.mkdir(File.join(root, "devices"))
      File.write(File.join(root, "devices", "a.json"), '{"device":"first"}')
      File.write(File.join(root, "devices", "b.json"), "private-broken-document")
      out, error = StringIO.new, StringIO.new
      adapter = double("adapter")
      command = CtxCli::Command.new(banner: "review", defaults: { batch: root }, out: out)
      entry = CtxCli::Review.new(command: command, directory: "devices", adapter: adapter, out: out, error: error)
      expect(entry.run([])).to eq(2)
      expect(error.string).to include("JSON::ParserError")
      expect(error.string).not_to include("private-broken-document")
      expect(out.string).to eq("")
      expect(out).not_to be_closed
    end
  end
end
