require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/fixtures/common'

describe "Dir.entries" do
  it "returns an Array of filenames in an existing directory including dotfiles" do
    a = Dir.entries(DirSpecs.mock_dir).sort

    a.should == DirSpecs.expected_paths

    a = Dir.entries("#{DirSpecs.mock_dir}/deeply/nested").sort
    a.should == %w|. .. .dotfile.ext directory|
  end
  
  ruby_version_is "1.9" do
    it "calls #to_path on non-String arguments" do
      p = mock('path')
      p.should_receive(:to_path).and_return(DirSpecs.mock_dir)
      Dir.entries(p)
    end
  end

  it "raises a SystemCallError if called with a nonexistent diretory" do
    lambda { Dir.entries DirSpecs.nonexistent }.should raise_error(SystemCallError)
  end
end
