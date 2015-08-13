
require 'scanf'

class CodeRunner
  # This is a class for running the luminescence code DosiVox. The idea is you prepare a pilot file with most of the information in it, but with a few tokens to be replaced on job submission. It also automates the generation of the dosimetry geometry.

  class Dosivox < Run

    @code_module_folder = File.expand_path(File.dirname(__FILE__))

    @variables = [:pilot_file, :ncopies, :dosivox_location, :concentrations]

    @substitutions = [:npart, :detvox, :detmat, :emitter, :detector, :particle, :cut, :nprobe, :nvx, :nvy, :nvz, :nsvx, :nsvy, :nsvz]

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
        if not @status == :Queueing
          if @percent_complete and @percent_complete < 100.0
            @status = :Incomplete
          else
            @status = :NotStarted
          end
        end
      else
        #3.times do
          #break if @percent_complete == 100.0
          #get_percent_complete
          #sleep 2
        #end
        if @percent_complete==100.0
          @status = :Complete
        else
          @status = :Failed
        end
      end
      get_averages if @percentages.find{|f| f==100.0}
      if FileTest.exist?('run_info.rb')
        @run_time = eval(File.read('run_info.rb'))[:elapse_mins]
      end
    end

    def get_percent_complete
      @percentages = @ncopies.times.map do |n|
        fname = "copies/#{n}/output"
        if FileTest.exist? fname
          text = File.read(fname)
          i = text.size - 1
          i-=1 while text[i] and text[i]!='%'
          text[i-3..i-1].to_f
        else
          0.0
        end
      end
      @percent_complete = @percentages.mean
    #rescue
      #@percent_complete = 0.0
    end

    def get_averages
      @material_averages = {}
      @material_results = {}
      @ncopies.times.each do |n|
        next unless @percentages[n] == 100.0
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
              @material_results[n][name] = [dose/em_mass, error/em_mass, Math.sqrt(error/em_mass/nsvox.to_f)].map{|f| f*100.0}
              @material_averages[name] ||= []
              @material_averages[name].push [dose/em_mass, Math.sqrt(error/em_mass/nsvox.to_f)].map{|f| f*100.0}
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
      line += sprintf(" %d mins ", @run_time) if @run_time
      line += @material_averages.map{|name, (val, error)| "#{name}: #{val} +/- #{error} %"}.join(",")  if @material_averages
      line += " -- #@comment" if @comment
      return line
    end

    def parameter_string
      "driver_script.rb"
    end

    def substitute_value(sub)
      case sub
      when :particle
        case send(sub)
        when :a, 1; '1'
        when :b, 2; '2'
        when :g, 3; '3'
        end
      when :emitter
        case send(sub)
        when :U, 1; '1'
        when :Th,2; '2'
        when :K, 3; '3'
        end
      when :detector
        case send(sub)
        when :Probe, 0; '0'
        when :Sub, 1; '1'
        end
      else
        send(sub).to_s
      end
    end
    def substitute_variables(text)
      (rcp.substitutions + [:run_name]).each do |sub|
        #eputs Regexp.new(sub.to_s.upcase), sub, send(sub)
        s = substitute_value(sub)
        raise "Bad value for #{sub}: #{s.inspect}" unless s and s.kind_of? String
        text.gsub!(Regexp.new(sub.to_s.upcase), s)
      end
    end
    def substitute_concentrations(text)
      #regex = Regexp.new("(?<voxelarray>(?:(?:(?:[\\d\\s]+){#@nvx}\\s*[\\n\\r]){#@nvy}\\s*[\\n\\r]){#@nvz})")
      #regex = Regexp.new("(?<voxelarray>(?:(?:(?:[\\d\\s]+){#@nvx}\\s*[\\n\\r]){1}\\s*[\\n\\r]){1})")
      voxelregex = Regexp.new("
        MEDIUM\\s+COMPOSITION.*[\\n\\r]+
        (?<voxelarray>
         (?:
           (?:
             [\\d \\t]+[\\n\\r]+
           ){#@nvy}\\s*[\\n\\r]
         ){#@nvz}
        )
       ", Regexp::EXTENDED)
      subvoxelregex = Regexp.new("
        VOXEL\\s+COMPOSITION.*[\\n\\r]+
        (?<subvoxelarray>
         (?:
           (?:
             [\\d \\t]+[\\n\\r]+
           ){#@nsvy}\\s*[\\n\\r]
         ){#@nsvz}
        )
       ", Regexp::EXTENDED)
      #p 'regex', voxelregex
      text =~ voxelregex
      voxelarray = $~[:voxelarray]
      text =~ subvoxelregex
      subvoxelarray = $~ ? $~[:subvoxelarray] : nil
      #p 'match is ', $~

      str = "abcdghijklmnopqrstuvwxyzABCDGHIJKLMN"
      # We substitute the letters first because there can be no
      # letter apart from e or f in the concentrations
      # so there are no unwanted double substitutions
      @concentrations.keys.each do |i|
        voxelarray.gsub!(Regexp.new("\\b#{i}\\b"), str[i])
        subvoxelarray.gsub!(Regexp.new("\\b#{i}\\b"), str[i]) if subvoxelarray
      end
      @concentrations.keys.each do |i|
        voxelarray.gsub!(Regexp.new("\\b#{str[i]}\\b"), @concentrations[i][@emitter].to_s)
        subvoxelarray.gsub!(Regexp.new("\\b#{str[i]}\\b"), @concentrations[i][@emitter].to_s ) if subvoxelarray
      end
      #p subvoxelarray
      text.sub!(/^VOXEL_CONCENTRATIONS[\n\r]{2}/, voxelarray.sub(/\r?\n\r?\n\Z/, ''))
      text.sub!(/^SUBVOXEL_CONCENTRATIONS[\n\r]{2}/, subvoxelarray)
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
            substitute_variables(text)
            substitute_concentrations(text)
            FileUtils.mkdir('data')
            File.open("data/#@run_name", 'w'){|f| f.puts text}
            FileUtils.mkdir('results')
            FileUtils.mkdir('results/DoseMapping')
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
  require 'pp'
  sleep 4
  run_info = {}
  run_info[:start_time] = Time.now.to_i
  nproc = #@nprocs
  #@ncopies.times.each do |n|
    fork do 
      Dir.chdir('copies/' + n.to_s) do
        IO.popen(%[#@dosivox_location/build/DosiVox > output 2>error], "w") do |pipe|
          pipe.puts "#@run_name\nno"
          pipe.close_write
        end
      end
    end
    if n%nproc == nproc-1
      puts "Waiting .. " + n.to_s 
      Process.wait
    end
  end
  Process.waitall
  sleep 2 # Allows IO to complete
  run_info[:end_time] = Time.now.to_i
  run_info[:elapse_mins] = (run_info[:end_time].to_f - run_info[:start_time].to_f)/60.0
  File.open("run_info.rb", "w"){|f| f.puts run_info.pretty_inspect}

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

