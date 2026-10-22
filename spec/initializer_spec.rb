# frozen_string_literal: true

RSpec.describe "Private configuration initialization" do
  it "does not publish a file when its new directory ancestry cannot be synchronized" do
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      target = File.join(root, "new", "nested", "settings.yml")
      allow(File).to receive(:open).and_wrap_original do |original, path, *args, **kwargs, &block|
        raise Errno::EIO if path == root
        original.call(path, *args, **kwargs, &block)
      end
      expect { CtxCli::Initializer.new.create(path: target, contents: "value: 1") }.to raise_error(Errno::EIO)
      expect(File.exist?(target)).to be(false)
    end
  end

  it "publishes complete private files once and retains existing content" do
    Dir.mktmpdir do |root|
      path = File.join(root, "private", "settings.yml")
      writer = CtxCli::Initializer.new
      expect(writer.create(path: path, contents: "a: 1\n")).to eq(:created)
      expect(File.stat(File.dirname(path)).mode & 0o777).to eq(0o700)
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect(writer.create(path: path, contents: "a: 2\n")).to eq(:exists)
      expect(File.read(path)).to eq("a: 1\n")
      expect(Dir.children(File.dirname(path))).to eq([ "settings.yml" ])
    end
  end

  it "refuses symlinks instead of treating them as an existing configuration" do
    Dir.mktmpdir do |root|
      path = File.join(root, "settings.yml")
      File.symlink(File.join(root, "absent"), path)
      expect { CtxCli::Initializer.new.create(path: path, contents: "private") }.to raise_error(ArgumentError)
      expect(File.symlink?(path)).to be(true)
    end
  end

  it "does not report success after publishing when directory sync fails" do
    Dir.mktmpdir do |root|
      path = File.join(root, "settings.yml")
      allow(File).to receive(:open).and_wrap_original do |original, *args, **keywords, &block|
        file = original.call(*args, **keywords, &block)
        allow(file).to receive(:fsync).and_raise(Errno::EIO) if args.first == File.realpath(root)
        file
      end
      expect { CtxCli::Initializer.new.create(path: path, contents: "complete") }.to raise_error(Errno::EIO)
      expect(File.read(path)).to eq("complete")
      expect(Dir.children(root)).to eq([ "settings.yml" ])
    end
  end
end
