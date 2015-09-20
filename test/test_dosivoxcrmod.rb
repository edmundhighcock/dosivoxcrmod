require 'helper'

class TestDosivoxcrmod < MiniTest::Test
  def test_submit
    tfolder = 'test/first_run'
    FileUtils.rm_r tfolder if FileTest.exist? tfolder
    FileUtils.makedirs(tfolder)
    File.open("#{tfolder}/dvox_defaults.rb", "w") do |file| 
      file.puts <<EOF
   @ncopies = 2
   @npart = 50
   @detvox = 1636
   @detmat = 0
   @cut = 0.01
   @nprobe = 7
   @emitter = :U
   @particle = :g
   @detector = 1
   @nvx = 15; @nvy = 12; @nvz = 10;
   @nsvx = 30; @nsvy = 30; @nsvz = 30;
   @concentrations = {
    0 => # Clay
      { U: 1.77, density: 1.6 },
    1 => # Fill
      { U: 1.51 },
    2 => # Gebel
      { U: 1.51 },
    3 => # Air
      { U: 0.0 },
    4 => # Residue
      { U: 1.51 },
    5 => # ClayBase
      { U: 1.77 },
   }
   @dosivox_location = #{(File.dirname(`which DosiVox`) + '/..').inspect}
   @pilot_file = #{File.expand_path('test/subvox').inspect}

EOF
    end
    CodeRunner.submit(Y: tfolder, p: '{}', n: '2', X: `which ruby`.chomp, C: 'dosivox', D: 'dvox')
  end
end
