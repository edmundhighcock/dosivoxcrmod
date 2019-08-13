
require 'scanf'

class CodeRunner
  # This is a class for running the luminescence code DosiVox. The idea is you prepare a pilot file with most of the information in it, but with a few tokens to be replaced on job submission. It also automates the generation of the dosimetry geometry.

  class Dosivox < Run

    @code_module_folder = File.expand_path(File.dirname(__FILE__))

    @variables = [:pilot_file, :ncopies, :dosivox_location, :concentrations]

    @substitutions = [:npart, :detvox, :detmat, :emitter, :detector, :particle, :cut, :nprobe, :nvx, :nvy, :nvz, :nsvx, :nsvy, :nsvz]

    @material_substitutions = [:density]

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
      (rcp.material_substitutions ).each do |sub|
        @concentrations.keys.each do |k|
          s = @concentrations[k][sub]
          next unless s
          text.gsub!(Regexp.new(sub.to_s.upcase + '_' + k.to_s), s.to_s)
        end
      end
    end
    def voxel_regex
      Regexp.new("
        MEDIUM\\s+COMPOSITION.*[\\n\\r]+
        (?<voxelarray>
         (?:
           (?:
             [\\d \\t]+[\\n\\r]+
           ){#@nvy}\\s*[\\n\\r]
         ){#@nvz}
        )
       ", Regexp::EXTENDED)
    end

    def subvoxel_regex
      Regexp.new("
        VOXEL\\s+COMPOSITION.*[\\n\\r]+
        (?<subvoxelarray>
         (?:
           (?:
             [\\d \\t]+[\\n\\r]+
           ){#@nsvy}\\s*[\\n\\r]
         ){#@nsvz}
        )
       ", Regexp::EXTENDED)
    end
    
    def substitute_concentrations(text)
      #regex = Regexp.new("(?<voxelarray>(?:(?:(?:[\\d\\s]+){#@nvx}\\s*[\\n\\r]){#@nvy}\\s*[\\n\\r]){#@nvz})")
      #regex = Regexp.new("(?<voxelarray>(?:(?:(?:[\\d\\s]+){#@nvx}\\s*[\\n\\r]){1}\\s*[\\n\\r]){1})")
      subvoxelregex = subvoxel_regex
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
      text.sub!(/^VOXEL_CONCENTRATIONS/, voxelarray.sub(/\r\n\r\n\Z/, ''))
      text.sub!(/^SUBVOXEL_CONCENTRATIONS/, subvoxelarray.sub(/\r\n\Z/, '')) if subvoxelarray
    end

    def generate_input_file
      @ncopies ||= 1
      FileUtils.mkdir("copies")
      File.open("driver_script.rb", 'w'){|f| f.puts driver_script}
      basetext = pilot_file_text
      @ncopies.times.each do |n|
        text = basetext.dup
        FileUtils.mkdir("copies/#{n}")
        Dir.chdir("copies/#{n}") do
          substitute_variables(text)
          substitute_concentrations(text)
          raise "Extra new line in pilot file" if text =~ /(\r\n){3}/
          raise "Line ending error" if text =~ /[^\r]\n/ # Files should have DOS line endings

          FileUtils.mkdir('data')
          File.open("data/#@run_name", 'w'){|f| f.puts text}
          FileUtils.mkdir('results')
          FileUtils.mkdir('results/DoseMapping')
          FileUtils.ln_s("#@dosivox_location/1run.mac", ".")
          FileUtils.ln_s("#@dosivox_location/data/Basic_Materials_List.txt", "data/.")
          FileUtils.ln_s("#@dosivox_location/data/spectra", "data/.")
        end
      end
    end

    def pilot_file_text
      if @pilot_file and FileTest.exist? @pilot_file
        basetext = File.read(@pilot_file)
      else
        raise "Please supply pilot_file, the name of the template pilot file. Please give the path of the file as abolute or relative to the run directory"
      end
      return basetext
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
    sleep 2 # Ensure the RNG is seeded differently
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
    
    def accumulated_mean(materialname)
      similar_runs = @runner.run_list.values.find_all{|r| (rcp.variables - [:npart, :ncopies]).inject(true){|b,v|  b && (send(v) == r.send(v))}}
      similar_runs.map{|r| r.material_averages[material_averages][0] * r.npar}.sum/similar_runs.map{|r| r.npart}.sum
    end

    def parameter_transition(run)
    end

    def generate_component_runs

    end

    def add_data(data, x, y, z, material) 
      data[0].push x
      data[1].push y
      data[2].push z
      data[3].push material
    end

    def showlayers(options={})
      Dir.chdir(@directory) do
        subvoxels = options[:subvoxels] ? true : false
        voxels = case subvoxels
                 when true
                   pilot_file_text =~ subvoxel_regex
                   $~[:subvoxelarray]
                 else
                   pilot_file_text =~ voxel_regex
                   $~[:voxelarray]
                 end
        #p voxels
        layers = voxels.split(/\r?\n\r?\n/)
        layer_data = []
        basefac = 0.0
        fac = 0.0
        upperfac = 0.0
        if options[:f_index]
          basefac = fac = options[:f_index].to_f / 100.0
          if subvoxels
            upperfac = [1.0, fac].min
            fac = [0.0, fac-1.0].max
          else
            fac = [1.0, fac].min
          end
        else
          fac = 1.0
        end
        subvoxel = [1, 1, 1] 
        subvoxel_mins = [0, 0, 0]
        subvoxel_maxes = [0, 0, 0]
        sx = sy = subvoxels ? 1 : 30
        sz = subvoxels ? 1 : 15
        dx = dy = subvoxels ? 1*fac : 10 * fac
        dz = subvoxels ? 4 * fac : 60 * fac
        xstart = ystart = zstart = 0
        puts(upperfac)
        xstart = ystart = -30.0 / 2
        zstart = -15.0 / 2
        if not subvoxels
          xstart = xstart - subvoxel[0] * (30.0 + 10.0 * fac) 
          ystart = ystart - subvoxel[1] * (30.0 + 10.0 * fac)
          zstart = zstart - subvoxel[2] * (15.0 + 40.0 * fac)
        end
        minfac = 4.0
        zmin = -sz * minfac + zstart
        xmin = -sx * minfac + xstart
        ymin = -sy * minfac + ystart
        zmax = xmax = ymax = 0
        maxfac = 3
        #for zi in 0...layers.size do
        z = zstart
        for zi in 0...layers.size do
          layer = layers[zi]
          blank = [NIL]*4
          y = ystart
          rows = layer.split(/\r?\n/)
          #for i in 0...rows.size do
          for i in 0...2 do
            row = rows[i]
              x = xstart
              voxels = row.split(/ /)
              #for j in 0...voxels.size do
              for j in 0...2 do
                material = voxels[j]
                if subvoxels or not [j, i, zi] == subvoxel
                  data = [[], [], [], []]
                  layer_data.push data
                  add_data(data,x,y,z,material)
                  add_data(data,x+sx,y,z,material)
                  add_data(data,*blank)
                  add_data(data,x,y+sy,z,material)
                  add_data(data,x+sx,y+sy,z,material)
                  if true or subvoxels
                    data = [[], [], [], []]
                    layer_data.push data
                    add_data(data,x,y,z+sz,material)
                    add_data(data,x+sx,y,z+sz,material)
                    add_data(data,*blank)
                    add_data(data,x,y+sy,z+sz,material)
                    add_data(data,x+sx,y+sy,z+sz,material)
                    data = [[], [], [], []]
                    layer_data.push data
                    add_data(data,x,y,z,material)
                    add_data(data,x,y+sy,z,material)
                    add_data(data,*blank)
                    add_data(data,x,y,z+sz,material)
                    add_data(data,x,y+sy,z+sz,material)
                    data = [[], [], [], []]
                    layer_data.push data
                    add_data(data,x+sx,y,z,material)
                    add_data(data,x+sx,y+sy,z,material)
                    add_data(data,*blank)
                    add_data(data,x+sx,y,z+sz,material)
                    add_data(data,x+sx,y+sy,z+sz,material)
                    data = [[], [], [], []]
                    layer_data.push data
                    add_data(data,x,y,z,material)
                    add_data(data,x+sx,y,z,material)
                    add_data(data,*blank)
                    add_data(data,x,y,z+sz,material)
                    add_data(data,x+sx,y,z+sz,material)
                    data = [[], [], [], []]
                    layer_data.push data
                    add_data(data,x,y+sy,z,material)
                    add_data(data,x+sx,y+sy,z,material)
                    add_data(data,*blank)
                    add_data(data,x,y+sy,z+sz,material)
                    add_data(data,x+sx,y+sy,z+sz,material)
                  end
                end
                if not subvoxels and j == subvoxel[0]
                  subvoxel_mins[0] = x
                  subvoxel_maxes[0] = x + sx
                end
                x = x + sx + dx
                xmax = x * maxfac
              end
            if not subvoxels and i == subvoxel[1]
              subvoxel_mins[1] = y
              subvoxel_maxes[1] = y + sy
            end
            y = y + sy + dy
            ymax = y * maxfac
          end 
          if not subvoxels and zi == subvoxel[2]
            subvoxel_mins[2] = z
            subvoxel_maxes[2] = z + sz
          end
          z = z + sz + dz
          zmax = z * maxfac
          #break
        end
        #$debug_gnuplot = true
        #pp layer_data
        gk = GraphKit.quick_create(*layer_data)
        gk.data.each do |dk|
          dk.gp.with = 'pm3d'
        end
        #gk2 = GraphKit.quick_create(*layer_data)
        #gk2.data.each do |dk|
          #dk.gp.with = 'p pointsize 0.1 linecolor "black" pt 1'
        #end
        gk.gp.view = [
          "equal xyz", #",,1,1"
          "60,#{20.0 + 10.0*basefac},,"
        ]
        gk.gp.key = "off"
        #gk.gp.xtics = gk.gp.ytics = gk.gp.ztics = "unset"
        gk.gp.xlabel = gk.gp.ylabel = gk.gp.zlabel = "unset"
        gk.gp.colorbox = "unset"
        gk.gp.size  = "2,2"
        gk.gp.origin = "-0.5,-0.5"
        gk.gp.zeroaxis = ""
        #gk.gp.zzeroaxis = "set"
        gk.gp.style = [
          "line 1 linecolor \"black\""
        ]
        margin = 0.5
        if not subvoxels
          gk.xrange = [xmin * (1.0-fac) + (subvoxel_mins[0]-dx*margin) * fac, 
                       xmax * (1.0-fac) + (subvoxel_maxes[0]+dx*margin) * fac
          ]
          gk.yrange = [ymin * (1.0-fac) + (subvoxel_mins[1]-dy*margin) * fac, 
                       ymax * (1.0-fac) + (subvoxel_maxes[1]+dy*margin) * fac
          ]
          gk.zrange = [zmin * (1.0-fac) + (subvoxel_mins[2]-dz*margin) * fac, 
                       zmax * (1.0-fac) + (subvoxel_maxes[2]+dz*margin) * fac
          ]
          #gk.xrange = [xmin, 
                       #xmax
          #]
          #gk.yrange = [ymin, 
                       #ymax
          #]
          #gk.zrange = [zmin, 
                       #zmax
          #]
          p ["MINS", zmin, subvoxel_mins[2], gk.zrange[0]]
        end

      

        nmaterials = 4
        colours = {0 => "#8e1f00",
                   1 => "#7f6c4d",
                   2 => "#835613",
                   3 => "#FFFFFF"
        }
        #colours = {0 => "slategrey",
                   #1 => "tan1",
                   #2 => "sandybrown",
                   #3 => "skyblue"
        #}
        colours = nmaterials.times.map do |ic|
          #value = (i).to_f / (nmaterials - 1).to_f
          "#{ic} \"#{colours[ic]}\""
        end
        gk.gp.cbrange = "[0:#{nmaterials-1}]"
        p gk.gp.palette = "defined (#{colours.join(", ")})"
        gk.gp.xyplane = "at 0"
        #gk.gp.border = "unset"
        gk.gp.pm3d = "depthorder hidden3d 1"
        gk.tile = nil
        gk.xlabel = nil
        gk.ylabel = nil
        gk.zlabel = nil
        gk.title = nil

        #gk.gp.pm3d = "depthorder"
        gk = gk #+ gk2
        return gk
      end
    end

    def graphkit(name, options)
      case name
      when 'showlayers'
        return showlayers(options)
      when 'empty'
      else
        raise 'Unknown graph'
      end
    end


  end
end

