
require 'scanf'

class CodeRunner
  # This is a class for running the luminescence code DosiVox. The idea is you prepare a pilot file with most of the information in it, but with a few tokens to be replaced on job submission. It also automates the generation of the dosimetry geometry.

  class Dosivox < Run

    @code_module_folder = File.expand_path(File.dirname(__FILE__))

    @variables = [:pilot_file, :ncopies, :dosivox_location]

    @substitutions = [:npart, :detvox, :concentrations, :emitter, :particle]

    @variables += @substitutions

    @naming_pars = []

    @results = [:material_averages, :material_results]

    @run_info = [ :percent_complete]

    @code_long = "DosiVox Luminescence Dose Rate Modeller"

    @excluded_sub_folders = ['data', 'results', 'copies']

    @modlet_required = false

    @uses_mpi = false

    def process_directory_code_specific
      get_percent_complete
      if @running
        @status ||= :Incomplete
      else
        @status = :Complete
      end
      get_averages if ctd
    end

    def get_percent_complete
      text = File.read('copies/0/output')
      i = text.size - 1
      i-=1 while text[i] and text[i]!='%'
      @percent_complete = text[i-3..i-1].to_f
    end

    def get_averages
      @material_averages = {}
      @material_results = {}
      @ncopies.times.each do |n|
        @material_results[n] = {}
        Dir.chdir("copies/#{n}") do
          case @detector
          when nil, 1 # Sub-voxelised voxel
            results = File.read("results/#{@run_name}_Detector1")
            # 0 Clay 1320 1.8 3 4.9482e-11 0 0
            lines = results.scan(/^\d+ \w+ \d+ [0-9.e\-+]+.*$/)
            lines.each do |l|
              _id, name, nsvox, _dens, _water_content, em_mass, dose, error = l.scanf("%d %s %d %f %f %f %f %f")
              p 'line is ', l
              @material_results[n][name] = [dose/em_mass, error/em_mass, Math.sqrt(error/em_mass/nsvox.to_f)]
              @material_averages[name] ||= []
              @material_averages[name].push [dose/em_mass, Math.sqrt(error/em_mass/nsvox.to_f)]
            end
          end
        end
      end
      @material_averages.keys.each do |name|
        dose_rates, errors = @material_averages[name].transpose
        @material_averages[name] = [dose_rates.mean, errors.mean, dose_rates.to_gslv.sd]
      end
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

  nproc = #@nprocs
  #@ncopies.times.each do |n|
    fork do 
      Dir.chdir('copies/' + n.to_s) do
        IO.popen(%[#@dosivox_location/build/DosiVox > output 2>error], "r+") do |pipe|
          pipe.puts "#@run_name\nno"
          pipe.close_write
          while ch = pipe.getc
            print ch
            if ch == "%"
               puts
            end
          end
        end
      end
    end
    if n%nproc == nproc-1
      puts "Waiting .. " + n.to_s 
      Process.wait
    end
  end
  Process.wait

EOF
    end

    def parameter_transition(run)
    end

    def generate_component_runs

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

