require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'close file after using it' do
    skip { "Decide on whether a file should be automatically closed upon first full iteration?" }
    options = {:col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/, :strings_as_keys => true}

    file = File.new("#{fixture_path}/binary.csv")

    SmarterCSV.process(file, options)

    file.closed?.should == true
  end
end
