# frozen_string_literal: true

require "yaml"

RSpec.describe "Host configuration" do
  it "does not claim applicable configuration after a later layer fails" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "sample.yml"), "enabled: true\n")
      broken = File.join(root, "broken.yml")
      File.write(broken, "invalid: [")
      files = CtxCli::Configuration.new(name: "sample", directories: [ root ], config: broken, env: {})
      expect { files.load }.to raise_error(ArgumentError)
      expect(files).to be_missing
      expect(files.data).to eq({})
      expect(files.config_files).to eq([])
      File.write(broken, "enabled: false\n")
      expect(files.load.data).to eq("enabled" => false)
      expect(files).not_to be_missing
    end
  end

  it "keeps field sources correct across scalar and mapping replacement" do
    Dir.mktmpdir do |root|
      first = File.join(root, "sample.yml")
      last = File.join(root, "override.yml")
      File.write(first, "a:\n  b: 1\nkeep: 2\nx: false\n")
      File.write(last, "a: false\nx:\n  y: 3\n")
      files = CtxCli::Configuration.new(name: "sample", directories: [ root ], config: last, env: {}).load
      expect(files.data).to eq("a" => false, "keep" => 2, "x" => { "y" => 3 })
      expect(files.sources.fetch("fields")).to eq("/a" => last, "/keep" => first, "/x/y" => last)
    end
  end

  it "tracks literal dotted and slashed keys separately from nested fields" do
    Dir.mktmpdir do |root|
      first = File.join(root, "sample.yml")
      last = File.join(root, "override.yml")
      File.write(first, { "a.b" => "literal", "a" => { "b" => "nested" }, "a/b" => "slash" }.to_yaml)
      File.write(last, { "a.b" => "changed" }.to_yaml)
      files = CtxCli::Configuration.new(name: "sample", directories: [ root ], config: last, env: {}).load
      expect(files.data).to eq("a.b" => "changed", "a" => { "b" => "nested" }, "a/b" => "slash")
      expect(files.sources.fetch("fields")).to eq("/a.b" => last, "/a/b" => first, "/a~1b" => first)
    end
  end

  it "removes only actual descendant sources when a mapping becomes a scalar" do
    Dir.mktmpdir do |root|
      first = File.join(root, "sample.yml")
      last = File.join(root, "override.yml")
      File.write(first, { "a" => { "b" => 1 }, "a.b" => 2, "a/b" => 3, "ab" => 4 }.to_yaml)
      File.write(last, { "a" => false }.to_yaml)
      files = CtxCli::Configuration.new(name: "sample", directories: [ root ], config: last, env: {}).load
      expect(files.data).to eq("a" => false, "a.b" => 2, "a/b" => 3, "ab" => 4)
      expect(files.sources.fetch("fields")).to eq("/a" => last, "/a.b" => first, "/a~1b" => first, "/ab" => first)
    end
  end

  it "preserves escaped empty and Unicode key identities through value replacement" do
    Dir.mktmpdir do |root|
      first = File.join(root, "sample.yml")
      last = File.join(root, "override.yml")
      File.write(first, { "" => { "~1" => "SYNTHETIC-SECRET" }, "~1" => { "/" => 1 },
        "é" => true, "e\u0301" => false, "items" => [ { "x" => 1 } ], "empty" => {}, "branch" => { "leaf" => 0 } }.to_yaml)
      File.write(last, { "" => { "~1" => nil }, "items" => [], "empty" => { "leaf" => false }, "branch" => {} }.to_yaml)
      files = CtxCli::Configuration.new(name: "sample", directories: [ root ], config: last, env: {}).load
      expect(files.data).to include("" => { "~1" => nil }, "items" => [], "empty" => { "leaf" => false }, "branch" => { "leaf" => 0 })
      expect(files.sources.fetch("fields")).to eq("//~01" => last, "/~01/~1" => first, "/é" => first, "/e\u0301" => first,
        "/items" => last, "/empty/leaf" => last, "/branch/leaf" => first)
      expect(files.sources.fetch("fields")).to be_frozen
      expect(files.sources.fetch("fields").keys).to all(be_frozen)
      expect(files.sources.to_s).not_to include("SYNTHETIC-SECRET")
    end
  end

  it "rejects excessive nesting through a controlled input error" do
    value = "leaf"
    6_000.times { value = [ value ] }
    expect { CtxCli::Configuration.copy(value) }.to raise_error(ArgumentError, /nesting/)
  end

  it "rejects excessive YAML nesting before recursive deserialization" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "sample.yml"), "value: " + "[" * 6_000 + "0" + "]" * 6_000)
      expect { CtxCli::Configuration.new(name: "sample", directories: [ root ], env: {}).load }.to raise_error(ArgumentError, /nesting/)
    end
  end

  it "loads a standalone tool file without a shared namespace" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "sample.yml"), "enabled: false\n")
      files = CtxCli::Configuration.new(name: "sample", directories: [ root ], env: {}).load
      expect(files.data).to eq("enabled" => false)
    end
  end

  def configuration(root, **options)
    CtxCli::Configuration.new(name: "audit", namespace: "suite", names: %w[audit archive], common_keys: %w[ssh],
      env: {}, directories: [ root ], home: root, cwd: root, path_fields: %w[directory ssh.known_hosts],
      env_path_keys: %w[DATA_PATH], **options)
  end

  it "loads a host-defined namespace, replaces arrays and resolves paths at their source" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "suite.yml"), { "common" => { "ssh" => { "known_hosts" => "keys" } },
        "audit" => { "devices" => [ "old" ], "enabled" => true } }.to_yaml)
      File.write(File.join(root, "audit.yml"), { "devices" => [], "enabled" => false, "optional" => nil, "directory" => "reports" }.to_yaml)
      files = configuration(root).load
      expect(files.data).to eq("ssh" => { "known_hosts" => File.join(root, "keys") }, "devices" => [],
        "enabled" => false, "optional" => nil, "directory" => File.join(root, "reports"))
      expect(files.sources.fetch("fields").fetch("/ssh/known_hosts")).to eq(File.join(root, "suite.yml"))
      expect(files.data.fetch("devices")).to be_frozen
    end
  end

  it "snapshots environment without mutating callers, ignores blank selectors and keeps secrets out of diagnostics" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".env"), "TOKEN='SYNTHETIC-SECRET'\nDATA_PATH=files\nAUDIT_CONFIG=chosen.yml\n")
      File.write(File.join(root, "chosen.yml"), "enabled: true\n")
      environment = { "AUDIT_CONFIG" => +"", "DATA_PATH" => +"process" }
      before = ENV.to_h
      files = configuration(root, env: environment).load
      environment.fetch("DATA_PATH").replace("changed")
      expect(files.environment.fetch("DATA_PATH")).to eq(File.join(root, "process"))
      expect(files.data).to eq("enabled" => true)
      expect(files.inspect + files.to_s + files.sources.inspect).not_to include("SYNTHETIC-SECRET")
      expect(ENV.to_h).to eq(before)
      File.write(File.join(root, "chosen.yml"), "enabled: false\n")
      expect(files.load.data).to eq("enabled" => true)
    end
  end

  it "rejects missing explicit files, ambiguous YAML and shell substitutions" do
    Dir.mktmpdir do |root|
      expect { configuration(root, config: "absent").load }.to raise_error(ArgumentError)
      [ "a: 1\na: 2\n", "---\na: 1\n---\nb: 2\n", "a: &a [1]\nb: *a\n" ].each do |contents|
        File.write(File.join(root, "audit.yml"), contents)
        expect { configuration(root).load }.to raise_error(ArgumentError)
      end
      File.write(File.join(root, ".env"), 'TOKEN=$(touch never)' + "\n")
      expect { configuration(root).load_environment }.to raise_error(ArgumentError)
      expect(File.exist?(File.join(root, "never"))).to be(false)
    end
  end

  it "snapshots environment selectors and path policies before loading files" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".env"), "CUSTOM_CONFIG=chosen.yml\nDATA_PATH=files\n")
      File.write(File.join(root, "chosen.yml"), "enabled: true\n")
      selector, path_key = +"CUSTOM_CONFIG", +"DATA_PATH"
      files = configuration(root, config_env: selector, env_path_keys: [ path_key ])
      selector.replace("CHANGED_CONFIG")
      path_key.replace("CHANGED_PATH")
      files.load
      expect(files.data).to eq("enabled" => true)
      expect(files.environment.fetch("DATA_PATH")).to eq(File.join(root, "files"))
    end
  end

  it "uses explicit line separators while reading dotenv" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".env"), "# comment\nA=one\nB=two\n")
      original = $/
      begin
        $/ = "!"
        expect(configuration(root).load_environment.environment).to include("A" => "one", "B" => "two")
      ensure
        $/ = original
      end
    end
  end

  it "rejects cyclic or opaque values without freezing caller-owned objects" do
    cycle = []; cycle << cycle
    opaque = Object.new
    expect { CtxCli::Configuration.copy(cycle) }.to raise_error(ArgumentError)
    expect { CtxCli::Configuration.copy({ "opaque" => opaque }) }.to raise_error(ArgumentError)
    expect(opaque).not_to be_frozen
  end
end
