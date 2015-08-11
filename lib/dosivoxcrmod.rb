

class CodeRunner
  # This is a class for running the luminescence code DosiVox. The idea is you pprepare a pilot file with most of the information in it, but with a few tokens to be replaced on job submission. It also automates the generation of the dosimetry geometry.
  
  class Dosivox < Run
    
@code_module_folder = File.expand_path(File.dirname(__FILE__))

@variables = [:pilot_file, :ncopies, :dosivox_location]

@substitutions = [:npart, :detvox, :concentrations, :emitter, :particle]

@variables += @substitutions

@naming_pars = []

@results = [:averages]

@run_info = [ :percent_complete]

@code_long = "DosiVox Luminescence Dose Rate Modeller"

@excluded_sub_folders = ['data', 'results', 'copies']

@modlet_required = false

@uses_mpi = false

def process_directory_code_specific
  if @running
    @status ||= :Incomplete
  else
    @status = :Complete
  end
  get_averages if ctd
end

def get_averages
end

def print_out_line
    line =  sprintf("%d:%d %30s %10s %s", @id, @job_no, @run_name, @status, @nprocs.to_s) 
    line += sprintf(" %3.1f\%", @percent_complete) if @percent_complete
    line += @averages.map{|name, (val, error)| "#{name}: #{val} +/- #{error} %"}.join(",")
    line += " -- #@comment" if @comment
    return line
end

def parameter_string
  "driver_script.rb"
end

def generate_input_file
  @ncopies ||= 1
  if @pilot_file and FileTest.exist? @pilot_file
    basetext = File.read(@pilot_file)
    FileUtils.mkdir("copies")
    File.open("driver_script.rb", 'w'){|f| f.puts driver_script}
    @ncopies.times.each do |n|
      text = basetext.dup
      FileUtils.mkdir("copies/#{n}")
      Dir.chdir("copies/#{n}") do
        (rcp.substitutions + [:run_name]).each do |sub|
          eputs Regexp.new(sub.to_s.upcase), sub, send(sub)
          text.gsub!(Regexp.new(sub.to_s.upcase), send(sub).to_s)
        end
        FileUtils.mkdir('data')
        File.open("data/#@run_name", 'w'){|f| f.puts text}
        FileUtils.mkdir('results')
        FileUtils.ln_s("#@dosivox_location/1run.mac", ".")
        FileUtils.ln_s("#@dosivox_location/data/Basic_Materials_List.txt", "data/.")
        FileUtils.ln_s("#@dosivox_location/data/spectra", "data/.")
      end
    end
  else
    raise "Please supply pilot_file, the name of the template pilot file. Please give the path of the file as abolute or relative to the run directory"
  end
end

def driver_script
  return <<EOF

  #@ncopies.times.each do |n|
    Dir.chdir('copies/' + n.to_s) do
      IO.popen("#@dosivox_location/build/DosiVox", "r+") do |pipe|
        pipe.puts "#@run_name\nno"
        pipe.close_write
        while line = pipe.gets
          puts line
        end
      end
    end
  end

EOF
end

def parameter_transition(run)
end

def generate_phantom_runs
end

def graphkit(name, options)
  case name
  when 'empty'
  else
    raise 'Unknown graph'
  end
end
    
    
  end
end

