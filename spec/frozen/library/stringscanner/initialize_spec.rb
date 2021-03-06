require File.dirname(__FILE__) + '/../../spec_helper'
require 'strscan'

describe "StringScanner#initialize" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "is a private method" do
    ruby_version_is "" ... "1.9" do
     @s.private_methods.should include('initialize')
    end
    ruby_version_is "1.9" do
      @s.private_methods.should include(:initialize)
    end
  end

  it "returns an instance of StringScanner" do
    @s.should be_kind_of(StringScanner)
    @s.tainted?.should be_false
    @s.eos?.should be_false
  end
end
