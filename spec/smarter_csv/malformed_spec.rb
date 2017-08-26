require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'malformed_csv' do
  subject { lambda { SmarterCSV.process(csv_path).to_a } }

  context "malformed header" do
    # TODO Should this be thrown on the initial parse rather than when you first begin reading?
    let(:csv_path) { "#{fixture_path}/malformed_header.csv" }
    it { should raise_error(CSV::MalformedCSVError) }
    it { should raise_error(/(Missing or stray quote in line 1|CSV::MalformedCSVError)/) }
    it { should raise_error(CSV::MalformedCSVError) }
  end

  context "malformed content" do
    let(:csv_path) { "#{fixture_path}/malformed.csv" }
    it { should raise_error(CSV::MalformedCSVError) }
    it { should raise_error(/(Missing or stray quote in line 1|CSV::MalformedCSVError)/) }
    it { should raise_error(CSV::MalformedCSVError) }
  end
end
