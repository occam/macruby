require File.dirname(__FILE__) + '/../../spec_helper'

ruby_version_is "1.9" do
  describe "File#reopen" do
    before :each do
      @file = tmp('test.txt')
      @fh = nil
      File.open(@file, "w") {|f| f << "1234567890"}
    end

    after :each do
      @fh.close if @fh
      File.delete(@file) if File.exists?(@file)
      @fh    = nil
      @file  = nil
    end

    it "resets the stream to a new file path" do
      @fh = File.new(@file)
      text = @fh.read
      @fh = @fh.reopen(@file, "r")
      @fh.read.should == text
    end

    it "accepts an object that has a #to_path method" do
      @fh = File.new(@file).reopen(mock_to_path(@file), "r")
    end
  end
end
