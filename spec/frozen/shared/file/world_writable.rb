require File.dirname(__FILE__) + '/../../spec_helper'

describe :file_world_writable, :shared => true do
  
  before(:each) do
    @file = tmp('world-writable')
    File.open(@file,'w') {|f| f.puts }
  end
  
  after(:each) do
    File.unlink(@file) if File.exists?(@file)
  end

  # These will surely fail on Windows.
  it "returns nil if the file is chmod 600" do
    File.chmod(0600, @file)
    @object.world_writable?(@file).should be_nil
  end

  it "returns nil if the file is chmod 000" do
    File.chmod(0000, @file)
    @object.world_writable?(@file).should be_nil
  end

  it "returns nil if the file is chmod 700" do
    File.chmod(0700, @file)
    @object.world_writable?(@file).should be_nil
  end

  # We don't specify what the Fixnum is because it's system dependent
  it "returns a Fixnum if the file is chmod 777" do
    File.chmod(0777, @file)
    @object.world_writable?(@file).should be_an_instance_of(Fixnum)
  end

  it "returns a Fixnum if the file is a directory and chmod 777" do
    dir = rand().to_s + '-ww'
    Dir.mkdir(dir)
    Dir.exists?(dir).should be_true
    File.chmod(0777, dir)
    @object.world_writable?(dir).should be_an_instance_of(Fixnum)
    Dir.rmdir(dir)
  end

  it "coerces the argument with #to_path" do
    obj = mock('path')
    obj.should_receive(:to_path).and_return(@file)
    @object.world_writable?(obj)
  end
end
