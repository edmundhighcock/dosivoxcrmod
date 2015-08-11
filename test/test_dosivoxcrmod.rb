require 'helper'

class TestDosivoxcrmod < MiniTest::Test
  def test_submit
    tfolder = 'test/first_run'
    FileUtils.rm_r tfolder if FileTest.exist? tfolder
    FileUtils.makedirs(tfolder)
    File.open("#{tfolder}/dvox_defaults.rb", "w") do |file| 
      file.puts <<EOF
   @npart = 1
   @dosivox_location = #{(File.dirname(`which DosiVox`) + '/..').inspect}
   @pilot_file = #{File.expand_path('test/subvox').inspect}
EOF
    end
    CodeRunner.submit(Y: tfolder, p: '{}', n: '1', X: `which ruby`.chomp, C: 'dosivox', D: 'dvox')
  end
end
