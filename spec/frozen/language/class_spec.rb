require File.dirname(__FILE__) + '/../spec_helper'
require File.dirname(__FILE__) + '/../fixtures/class'

ClassSpecsNumber = 12

module ClassSpecs
  Number = 12
end

describe "A class definition" do
  it "creates a new class" do
    ClassSpecs::A.class.should == Class
    ClassSpecs::A.new.class.should == ClassSpecs::A
  end

  it "has no class variables" do
    ClassSpecs::A.class_variables.should == []
  end

  ruby_version_is "" ... "1.9" do
    it "raises TypeError if constant given as class name exists and is not a Module" do
      lambda {
        class ClassSpecsNumber
        end
      }.should raise_error(TypeError)
    end
  end

  # test case known to be detecting bugs (JRuby, MRI 1.9)
  it "raises TypeError if the constant qualifying the class is nil" do
    lambda {
      class nil::Foo
      end
    }.should raise_error(TypeError)
  end

  it "raises TypeError if any constant qualifying the class is not a Module" do
    lambda {
      class ClassSpecs::Number::MyClass
      end
    }.should raise_error(TypeError)

    lambda {
      class ClassSpecsNumber::MyClass
      end
    }.should raise_error(TypeError)
  end

  it "allows using self as the superclass if self is a class" do
    ClassSpecs::I::J.superclass.should == ClassSpecs::I

    lambda {
      class ShouldNotWork < self; end
    }.should raise_error(TypeError)
  end

#  # I do not think this is a valid spec   -- rue
#  it "has no class-level instance variables" do
#    ClassSpecs::A.instance_variables.should == []
#  end

  it "allows the declaration of class variables in the body" do
    ClassSpecs::B.should have_class_variable(:@@cvar)
    ClassSpecs::B.send(:class_variable_get, :@@cvar).should == :cvar
  end

  it "stores instance variables defined in the class body in the class object" do
    ClassSpecs::B.should have_instance_variable(:@ivar)
    ClassSpecs::B.instance_variable_get(:@ivar).should == :ivar
  end

  it "allows the declaration of class variables in a class method" do
    ClassSpecs::C.class_variables.should == []
    ClassSpecs::C.make_class_variable
    ClassSpecs::C.should have_class_variable(:@@cvar)
  end

  it "allows the definition of class-level instance variables in a class method" do
    ClassSpecs::C.should_not have_instance_variable(:@civ)
    ClassSpecs::C.make_class_instance_variable
    ClassSpecs::C.should have_instance_variable(:@civ)
  end

  it "allows the declaration of class variables in an instance method" do
    ClassSpecs::D.class_variables.should == []
    ClassSpecs::D.new.make_class_variable
    ClassSpecs::D.should have_class_variable(:@@cvar)
  end

  it "allows the definition of instance methods" do
    ClassSpecs::E.new.meth.should == :meth
  end

  it "allows the definition of class methods" do
    ClassSpecs::E.cmeth.should == :cmeth
  end

  it "allows the definition of class methods using class << self" do
    ClassSpecs::E.smeth.should == :smeth
  end

  it "allows the definition of Constants" do
    Object.const_defined?('CONSTANT').should == false
    ClassSpecs::E.const_defined?('CONSTANT').should == true
    ClassSpecs::E::CONSTANT.should == :constant!
  end

  it "returns the value of the last statement in the body" do
    class ClassSpecs::Empty; end.should == nil
    class ClassSpecs::Twenty; 20; end.should == 20
    class ClassSpecs::Plus; 10 + 20; end.should == 30
    class ClassSpecs::Singleton; class << self; :singleton; end; end.should == :singleton
  end
end

describe "An outer class definition" do
  it "contains the inner classes" do
    ClassSpecs::Container.should have_constant(:A)
    ClassSpecs::Container.should have_constant(:B)
  end
end

describe "A Class Definitions extending an object" do
  it "allows adding methods" do
    ClassSpecs::O.smeth.should == :smeth
  end

  it "raises a TypeError when trying to extend numbers" do
    lambda {
      eval <<-CODE
        class << 1
          def xyz
            self
          end
        end
      CODE
    }.should raise_error(TypeError)
  end
end

describe "Reopening a class" do
  it "extends the previous definitions" do
    c = ClassSpecs::F.new
    c.meth.should == :meth
    c.another.should == :another
  end

  it "overwrites existing methods" do
    ClassSpecs::G.new.override.should == :override
  end

  it "raises a TypeError when superclasses mismatch" do
    lambda { class ClassSpecs::A < Array; end }.should raise_error(TypeError)
  end

  it "adds new methods to subclasses" do
    lambda { ClassSpecs::M.m }.should raise_error(NoMethodError)
    class ClassSpecs::L
      def self.m
        1
      end
    end
    ClassSpecs::M.m.should == 1
  end
end

describe "class provides hooks" do
  it "calls inherited when a class is created" do
    ClassSpecs::H.track_inherited.should == [ClassSpecs::K]
  end
end
