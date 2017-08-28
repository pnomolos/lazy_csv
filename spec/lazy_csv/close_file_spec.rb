require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'should close a filename after using it' do
    options = {:col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/, :strings_as_keys => true}

    enumerator = LazyCSV.process("#{fixture_path}/binary.csv", options)
    enumerator.to_a.size.should == 8

    enumerator.instance_variable_get(:@io).closed?.should == true

    enumerator = LazyCSV.process("#{fixture_path}/binary.csv", options)
    enumerator.each { }

    enumerator.instance_variable_get(:@io).closed?.should == true
  end

  it "shouldn't close an IO instance after using it" do
    options = {:col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/, :strings_as_keys => true}

    file = File.new("#{fixture_path}/binary.csv")

    LazyCSV.process(file, options).to_a

    file.closed?.should == false
    file.close
  end
end
