# Add default parameter values to Spice/Spectre model
#    (C)Seijiro Moriyama, seijiro.moriyama@anagix.com
=begin
/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/
=end
# usage:
#     spice_addd input_model_file[, default_parameters_file]

require 'rubygems'
require 'ruby-debug'

class Converter
  def numeric?(object)
    true if Float(object) rescue false
  end
  
  def unwrap netlist, ignore_comments=true    # line is like:
#    puts '*** unwrap *** unwrap *** unwrap *** unwrap *** unwrap *** unwrap ***'
    result = ''         # abc
    breaks = []         #+def   => breaks[0]=[3]
#prof_result = RubyProf.profiler {
    pos = 0
    line = '' 
    bs_breaks = []
    netlist && netlist.each_line{|l|  # line might be 'abc\n' or 'abc\r\n'
      next if ignore_comments && (l[0,1] == '*' || l[0,1] == '/') # just ignore comment lines
#puts l
#      l_chop = l.dup
#      l_chop[-2,2] == '' if l_chop[-2,2] == "\r\n"
#      l_chop[-1,1] == '' if l_chop[-1,1] == "\n"
      l_chop = l.chop
#      if l.chop[-1,1] == "\\"
      if l_chop[-1,1] == "\\"
        line << l_chop
        line[-1,1] = ' '   # replace backslash with space
        bs_breaks << -(line.length-1)   # record by minus number
        next
      end
      line << l
      if /^\+/ =~ line
#        result.chop!          # remove \r and \n
        result[-2,2] = '' if  result[-2,2] == "\r\n"
        result[-1,1] = '' if  result[-1,1] == "\n"
        result << ' ' if result[-1,1] != ' ' && line[1,1] != ' '
        breaks[-1] << result.length - pos
        bs_breaks.each{|bs|
          breaks[-1] << -(result.length + (-bs)-1)  # -1 is to adjust for +
        }
        result << line[1..-1]
      else
        pos = result.length
        result << line
        #      breaks << []
        breaks << bs_breaks
      end
      bs_breaks = []
#puts "line: #{line}"
      line = ''
    }
#}
#puts prof_result
    [result, breaks]
  end

  def remove_unsupported_parameters! description, model_parameters, unsupported, tool='LTspice'
    return description if unsupported.size == 0
    deleted = "*Notice: parameters unsupported by #{LTspice} removed\n"
    i = 0
    unsupported.each{|p|
      next if model_parameters[p].nil?
      description.sub!(" #{p}=#{model_parameters[p]}", '')
      description.sub!("+#{p}=#{model_parameters[p]}", '+')
      if i % 4 == 0
        deleted << "* #{p}=#{model_parameters[p]}" 
      elsif i % 4 == 3
        deleted << " #{p}=#{model_parameters[p]}\n"
      else
        deleted << " #{p}=#{model_parameters[p]}"
      end
      i = i + 1
    }
    if i > 0
      description << deleted +"\n"
    else
      description
    end
  end  

  def replace_model_parameter description, model_parameters, a, b
#      description.sub!(/tref *= *#{model_parameters['tref']}/, "tnom = #{model_parameters['tref']}")
    description.sub!(/#{a} *= *#{model_parameters[a]}/, "#{b} = #{model_parameters[a]}")
  end
end

class Spectre_to_SPICE < Converter
  def convert_model_library description
    description = spectre_to_spice description
    return description
  end

  MODEL_TYPE_TO_SYMBOL = {'diode' => 'd', 'DIODE' => 'D',
    'bjt' => 'q', 'BJT' => 'Q', 'hbt' => 'q', 'HBT' => 'Q',
    'vbic' => 'q', 'VBIC' => 'Q', 'ekv' => 'm', 'EKV' => 'M', 
    'bsim1' => 'm', 'BSIM1' => 'M', 'bsim2' => 'm', 'BSIM2' => 'M', 
    'bsim3' => 'm', 'BSIM3' => 'M', 'bsim3v3' => 'm', 'BSIM3v3' => 'M', 
    'bsim4' => 'm', 'BSIM4' => 'M', 'hvmos' => 'm', 'HVMOS' => 'M',
    'hisim' => 'm', 'HISIM' => 'M', 'bsimsoi' => 'm', 'BSIMSOI' => 'M',
    'jfet' => 'j', 'JFET' => 'J',
    'capacitor' => 'c', 'CAPACITOR' => 'C', 'resistor' => 'r', 'RESISTOR' => 'R'
  } unless defined? MODEL_TYPE_TO_SYMBOL

  def convert_if_else_clause description
    lines = ''
    depth = 0  
    description.each_line{|l|
#debugger if l=~/(ELSE|else)/
      if l =~ /^ *(if|IF)([\( ]+.*) *\{/
        l.sub! $&, ' '*depth + "IF #{$2}"
        puts l
        depth = depth + 1
      elsif depth > 0
        if l =~ /^ *\} *(else|ELSE) +(if|IF)([\( ]+.*) *\{/
          l.sub! $&, ' '*(depth-1) + "ELSE IF #{$3}"
          puts l
        elsif l =~ /^ *\} *(else|ELSE) *\{ *$/
          l.sub! $&, ' '*(depth-1) + 'ELSE'
          puts l
        elsif l =~ /^ *\} *$/
          depth = depth - 1
          l.sub! $&, ' '*depth + 'END'
          puts l
        end
      end
      lines << l
    }
    lines
  end

  def spectre_to_spice description
    return nil unless description
    spice_model = ''
    model_name = nil
    model_type = nil
    subckt_name = nil
    flag = nil  # lang=spice if true
    binflag = nil
    binnumber = 0
#    unwrapped = nil
#    breaks = nil
#result = RubyProf.profiler {
    unwrapped, breaks = unwrap description    # continuation w/ '+' unwrapped    
#}
#puts result
    count = -1
#    unwrapped.gsub(/\\\r*\n/, '').each_line{|l|
    unwrapped.each_line{|l|
      count = count + 1
      wl = wrap(l, breaks[count])
# puts "wl:#{wl.inspect}"
      next if wl =~ /^ *\*/ && !(wl =~ /\n.+$/) ### erase single comment lines 
                                                ### leave comment wrapped inside continuation
      if binflag
        if wl.include? '}' 
          binflag = nil
        elsif wl =~ /^ *\*/
          spice_model << wl
        elsif wl =~ /^ *\/\//
          spice_model << '*' + wl[2..-1]
        else
          # wl is like '0: type=n\n+ lmin=...\n...' 
          binnumber, s = wl.split(/: */)
#          spice_model << ".model #{model_name}.#{binnumber.to_i+1} #{model_type} " + s
          spice_model << ".model #{model_name}.#{binnumber} #{model_type} " + s
        end

      elsif wl =~ /^ *\) *$/            #### very special handling for HSPICE model
        spice_model << wl.sub(/^ */,'+') #### ending the model with only ')' 

      elsif wl =~ /^ *\/\//
        spice_model << '*' + wl[2..-1]
      elsif wl =~ /^ *\.*model +(\w+) +(\w+)/ || wl =~ /^ *\.*MODEL +(\w+) +(\w+)/
        model_name = $1
        model_type = $2
#        puts "*** spectre_to_spice for model: #{model_name} type: #{model_type} ***"
        if $2 == 'diode' || $2 == 'DIODE'
          wl.sub!(/#{model_type}/, 'd')
        end
        unless wl.include? '{'
          if flag || wl.downcase =~ /\.model/
            spice_model << wl
          else
            spice_model << wl.sub(/^ */,'.') # what is this for ??? lang=spectre???
          end
        else # binned model (model selection in Spectre)
          binflag = true
        end
      elsif wl =~ /simulator +lang *= *spectre/
        flag = nil
        next
      elsif wl =~ /simulator +lang *= *spice/
        flag = true
        next
      elsif flag
        spice_model << wl
        next
      elsif wl =~ /^ *#/
        spice_model << wl
      elsif wl =~ /^ *parameters/ || wl =~ /^ *PARAMETERS/
        pairs, singles = parse_parameters(l)
        singles && singles.each{|s| wl.sub!(/ #{s} /, " #{s}=0 ")}
        if pairs
          wl.sub!(/ *= */, '=')
#          pairs.each_pair{|k, v|
#            wl.sub!("#{k}=#{v}", "#{k}={#{v}}") unless numeric? v
#          }
        end
	spice_model << wl.sub('parameters', '.param').sub('PARAMETERS', '.PARAM')
      elsif wl =~ /^ *inline +subckt +(\S+)/
        subckt_name = $1
        spice_model << wl.sub(/^ *inline +subckt/, '.subckt').sub(/^ *INLINE +SUBCKT/, '.SUBCKT')
      elsif wl =~ /^ *subckt +/ || wl =~ /^ *parameters +/ || wl =~ /^ *include +/
        spice_model << wl.sub(/^ */,'.')
      elsif wl =~ /^ *ends/ || wl =~ /^ *ENDS/ 
        spice_model << wl.sub(/^ */,'.')
      else
        spice_model << wl
      end
    }
    puts "binnumber = #{binnumber}" if binnumber > 0
    if binnumber.to_i == 1
      spice_model.sub! ".model #{model_name}.#{binnumber}", ".model #{model_name}" 
    end
    return spice_model unless subckt_name
    new_model = ''
    unwrapped, breaks = unwrap spice_model
    count = -1
    unwrapped.each_line{|l|
      count = count + 1
      wl = wrap(l, breaks[count])
#puts wl
      if l =~ /(^ *)(\S+) (\([^\)]*\)) +#{model_name} +(.*)$/
        parms, = parse_parameters $4
#        wl.sub! $2, MODEL_TYPE_TO_SYMBOL[model_type]+$2
        unless MODEL_TYPE_TO_SYMBOL[model_type].nil?
          wl.sub! $2, MODEL_TYPE_TO_SYMBOL[model_type]+$2  ### what was this for??? for LPNP???
        end
        wl.sub!(/ *= */, '=')
        parms.each_pair{|k, v|
          if k == 'region'
            wl.sub!("#{k}=#{v}", '')
          else
            wl.sub!("#{k}=#{v}", "#{k}={#{v}}") unless numeric?(v)
          end
        }
      end
      new_model << wl
    }
    new_model
  end
end

module SpectreParser
  private
  def eng val, multiplier=nil
    if val =~ /([0-9.]+)M/
      val = $1 + 'MEG'
    end
    if val ### && @param # && @param.include?(val)
      unless numeric?(val)
        if multiplier == -1
          return "{#{convert_to_if val}/m}" 
        elsif multiplier
          return "{#{convert_to_if val}*m}" 
        else
          return "{#{convert_to_if val}}" 
        end
      end
      return val
    end
    '' # changed from nil
  end

  def rest_parms line, subckt_for_model=nil
    return line if line == ''
    puts "line: #{line.downcase}"
    l = line.dup
    l.gsub!(/ *= */, '=')
    p, = parse_parameters l
    flag = subckt_for_model
    p.each_pair{|k, v|
      if subckt_for_model &&  k == 'm'
        l.sub!("#{k}=#{v}", "#{k}=#{eng(v, true)}")
        flag = nil
      else
        l.sub!("#{k}=#{v}", "#{k}=#{eng(v)}")
      end
    }
    l << ' m={m}' if flag
    l
  end

  def eng2 val
    #  puts "eng2=#{val}"
    return val if val == "\"\"" # to avoid case value={""}
    return '0.0' if val.nil? ### return 0.0 as a default 
    if val =~ /([0-9.]+)M/
      val = $1 + 'MEG'
    end
    return "{#{val}}" unless numeric?(val) || eng?(val) || val.strip.start_with?('{')
    val
  end
  
  def supress_defaults p, *names
    valid_names = names.dup
    names.reverse.each{|n|
      param = p[n]
      break unless param.nil?
      valid_names.delete n
    }
    result = ''
    valid_names.each{|n|
      param = p[n]
      result << " #{eng2 param}"
    }
    result
  end

  def parse_src line
    result = ''
    p, = parse_parameters line
#    if @param
#      p.each_pair{|k, v|
#        if @param.include? v
#          p[k] = '{' + v + '}'
#        end
#      }
#    end
    case p['type']
    when 'dc'
      result << "#{eng(p['dc'])}"
    when 'pulse'
      # V1 V2 Tdelay Trise Tfall Ton Tperiod Ncycles 
      result << "PULSE#{supress_defaults p, 'val0', 'val1', 'delay', 'rise', 'fall', 'width', 'period'}"
    when 'pwl'
      wave = p['wave']  # wave = '[...]'
      if wave =~ /\[ *(.*) *\]/
        wave = $1.strip
      end
      result << "PWL (#{wave})"
    when 'sine'
      # Voffset Vamp Freq Td Theta Phi Ncycles
      result << "SINE#{supress_defaults p, 'sinedc', 'ampl', 'freq', 'delay', 'damp', 'sinephase'}"
    when 'exp'
      # V1 V2 Td1 Tau1 Td2 Tau2
      result << "EXP#{supress_defaults p, 'val0', 'val1', 'td1', 'tau1', 'td2', 'tau2'}"
    end
    if p['mag'] 
      result << " AC #{eng(p['mag'])}"
    end
    result.gsub(/ +/, ' ')
  end

  def parse_options line
    params, = parse_parameters line
    result = ''
    result << " temp=#{params['temp']}" if params['temp']
    result << " tnom=#{params['tnom']}" if params['tnom']
    result << " reltol=#{params['reltol']}" if params['reltol']
    result << " vntol=#{params['vabstol']}" if params['vabstol']
    result << " abstol=#{params['iabstol']}" if params['iabstol']
    result << " gmin=#{params['gmin']}" if params['gmin']
    result
  end

  def parse_dc_sweep line
    p = parse line
    step = p['step']
    "#{p['start']} #{p['stop']} #{step}"
  end

  def parse_ac_sweep line
    p = parse line
    result = ''
    result << "lin #{p['step']}" if p['step']
    result << "dec #{p['dec']}" if p['dec']
    result << "oct #{p['oct']}" if p['oct']
    result << "dec 50" unless (p['step'] || p['dec'] || p['oct'])
    result << " #{eng p['start']} #{eng p['stop']}"
  end

  def parse line
    parameters = {}
    line && line.split.each{|a| 
      k, v = a.split('=')
      parameters[k] = v
    }
    parameters
  end
end

class Spectre_to_LTspice < Spectre_to_SPICE
  include SpectreParser
  @@parenthesis_strip = false

  def initialize defaults, case_='upcase'
    @case = case_ 
    @spice_defaults = {}
    defaults.each{|p, v|
      @spice_defaults[p] = v.to_s
    }
  end

  def add_defaults parms, name, type, case_= nil
    case_ ||= @case
    defaults = @spice_defaults
    parms.each_pair{|p, v|
      pcap = p.send case_ 
      defaults[pcap] = v
    }
    defaults
  end

  def slice_section description
    header = ''
    footer = ''
    body = ''
    bodies = {}
    flag = nil
    section = nil
    description.each_line{|l|
      if flag
        if l=~ /endsection /
          bodies[section] = body
          flag = false
        else
          body << l
        end
      elsif l=~ /section *(\S+)/
        section = $1
        flag = true
        body = ''
      elsif bodies.size == 0
        header << l
      else
        footer << l
      end
    }
    return [nil, nil, nil] if bodies.size == 0
    [header, bodies, footer]
  end

  def convert_model description, param_vals=nil
    downcase_flag = false
    downcase_flag = true if description == description.downcase
    if description =~ /^ *subckt / || description =~ /^ *inline +subckt /
      description = convert_if_else_clause description
      result = convert_netlist description, param_vals, true
      return downcase_flag && result || result.upcase
    end
    description = spectre_to_spice description.downcase
    description = convert_if_else_clause description
    header, bodies, footer = slice_section description
    if bodies
      result = header
      bodies.each_pair{|sect, desc|
        result << "section #{sect}\n"
        result << convert_model_sub(desc, param_vals)
        result << "endsection #{sect}\n"
      }
      result << footer
    else
      result = ''
      description.split('.model ').each{|m|
        next if m.strip == ''
        if m.start_with?('.') && !m.start_with?('.model')
          result << m
        else
          result << convert_model_sub('.model ' + m, param_vals)
        end
      }
    end
    downcase_flag && result || result.upcase
  end
  
  def convert_model_sub description, param_vals # param_vals is not officially used yet
    description.downcase! # notice: only downcase works!
    description.gsub!(/ *= */, '=')
    type, name, model_parameters = parse_model description
    if type == 'bjt'
      description.gsub!(/^.*\.model +\S+ +bjt/,".model #{name} #{model_parameters['type']}") 
      description.gsub!(/type *= *#{model_parameters['type']}/, '')
      type = model_parameters['type']
    end
    if type =~ /pnp/ || type == 'npn'
      replace_model_parameter description, model_parameters, 'tref', 'tnom'
      replace_model_parameter description, model_parameters, 'nkf', 'nk'
      remove_unsupported_parameters! description, model_parameters, %w[compatible minr compatible]
      if model_parameters['struct']
        if model_parameters['struct'] == 'vertical'
          description.gsub!(/struct *= *#{model_parameters['struct']}/, 'subs = 1')
        elsif model_parameters['struct'] == 'lateral'
          description.gsub!(/struct *= *#{model_parameters['struct']}/, 'subs = 2')
        end
      end
    elsif type == 'd' || type =='diode'
      replace_model_parameter description, model_parameters, 'tref', 'tnom'
      replace_model_parameter description, model_parameters, 'ik', 'ikf'
      replace_model_parameter description, model_parameters, 'pb', 'vj'
      replace_model_parameter description, model_parameters, 'cj', 'cjo'
      replace_model_parameter description, model_parameters, 'trs', 'trs1'
      description.gsub! ' diode', ' d'
      remove_unsupported_parameters! description, model_parameters, %w[dskip minr imax]
    end
    if type == 'pnp'
      if model_parameters['subs']
        if model_parameters['subs'].to_i == -1 || model_parameters['struct'] == 'lateral'
          description.gsub!(/subs *= *#{model_parameters['subs']}/, 'subs = 2')
        end
      end
    elsif type == 'vbic'
      replace_model_parameter description, model_parameters, 'tref', 'tnom'
      type = model_parameters['type']
      description.gsub!(/vbic +type *= *#{type}/, "#{type} level = 9")
      remove_unsupported_parameters! description, model_parameters, %w[version minr]
    elsif type == 'nmos' || type == 'pmos'
#      if (level=model_parameters['level'])=='11' || level=='49' || level=='53'
#        result = description.gsub(/level *= *#{level}/, 'level = 8')
      if (level=model_parameters['level'])=='11' || level=='53'
        description.gsub!(/level *= *#{level}/, 'level = 49')
      end
    elsif type == 'bsim3v3'
      polarity = model_parameters['type'] 
      description.gsub!(/level *= *[0-9]+/, '')
#      result = description.gsub(/bsim3v3 +type *= *#{polarity}/, "#{polarity}mos level = 8")
      description.gsub!(/bsim3v3 +type *= *#{polarity}/, "#{polarity}mos level = 49")
#                    changed to level = 49 to support xl and xw
#                    see => HSPICE level 49 model in LTSPICE (http://www.electronicspoint.com/hspice-level-49-model-ltspice-t30206.html)
#      result.gsub! /minr *= *#{model_parameters['minr']}/, '' # remove minr
      remove_unsupported_parameters! description, model_parameters, %w[minr hdif ldif tlev tlevc xl xw lmlt wmlt diomod]
    elsif type == 'bsim4'
      polarity = model_parameters['type'] 
      description.gsub!(/bsim4 +type *= *#{polarity}/, "#{polarity}mos level = 14")
      remove_unsupported_parameters! description, model_parameters, %w[minr imax]
    elsif type == 'hisim_hv'
      polarity = model_parameters['type'] 
      description.gsub!(/hisim_hv +type *= *#{polarity}/, "#{polarity}mos") # leve=73 works as it is
      remove_unsupported_parameters! description, model_parameters, %w[minr imax]
    elsif type == 'jfet'
      polarity = model_parameters['type'] 
      description.gsub!(/jfet +type *= *#{polarity}/, "#{polarity}jf")
      
    elsif type == 'r'
#      model_parameters.delete 'scale'
      result = ".subckt #{name} n p\n"
      params = model_parameters.map{|p| "#{p[0]}=#{p[1]}"}.join(' ')
      result << ".param r=0 #{params}\n"
      scale = model_parameters.delete 'scale'
      params = model_parameters.map{|p| "#{p[0]}={#{p[0]}}"}.join(' ')
      if scale
        result << "r n p {r*#{scale}} #{params}\n"
      else
        result << "r n p {r} #{params}\n"
      end
      result << ".ends #{name}\n"
      return result
    elsif type == 'c'
#      model_parameters.delete 'scale'
      model_parameters.delete 'tc1'
      model_parameters.delete 'tc2'
      result = ".subckt #{name} n p\n"
      params = model_parameters.map{|p| "#{p[0]}=#{p[1]}"}.join(' ')
      result << ".param c=0 #{params}\n"
      scale = model_parameters.delete 'scale'
      params = model_parameters.map{|p| "#{p[0]}={#{p[0]}}"}.join(' ')
      if scale
        result << "c n p {c*#{scale}} #{params}\n"
      else
        result << "c n p {c} #{params}\n"
      end
      result << ".ends #{name}\n"
      return result
    elsif type == 'capacitor'
      result = description.sub /\.model.*capacitor/, ".subckt #{name} 1 2\n.param m=1"
      result << "+ area_eff = {(l - 2*etch)*(w - 2*etch)}\n"
      result << "+ perim_eff = {2 *(w + l - 4*etch)}\n"
      result << "c 1 2 {(cj*area_eff + cjsw*perim_eff)*m}\n"
      result << ".ends #{name}\n"
      return result
    elsif type == 'resistor'
      result = description.sub /\.model.*resistor/, ".subckt #{name} 1 2\n.param m=1"
      result << "r 1 2 {(rsh/m) * (l - 2 * etchl) / (w - 2 * etch)} tc1={tc1} tc2={tc2}\n"
      result << ".ends #{name}\n"
      return result
    else
      raise "error: model type ='#{type}' is not supperted!"
    end
    if @spice_defaults && @spice_defaults.size > 0
      model_parameters = add_defaults model_parameters, name, type
      description = description.send @case
    end
    count = 0
    model_parameters && model_parameters.map{|p|          # convert HSPICE style equations to LTspice style
      puts "#{p[0]}=>#{p[1]}"
      next if p[0] == 'type'
      next if p[1].nil? || p[1].start_with?('[')
      if p[1].start_with?("'") && p[1].end_with?("'")
        value = p[1][1..-2].gsub('temper', 'temp')
        converted_value = convert_to_if value
        description.gsub!(" #{p[0]}=#{value}", " #{p[0]}=\{#{converted_value}\}")
        description.gsub!("+#{p[0]}=#{value}", "+#{p[0]}=\{#{converted_value}\}")
      else
        value=p[1]
        unless description =~/[ +]#{p[0]}\t*=/
          description << " #{p[0]}=#{value}"
          count = count + 1
          description << "\n" if count % 7 == 0
          next
        end
        unless numeric? value
          if param_vals && val=param_vals[value]
            description.gsub!(" #{p[0]}=#{value}", " #{p[0]}=#{val}")
            description.gsub!("+#{p[0]}=#{value}", "+#{p[0]}=#{val}")
          else
            converted_value = convert_to_if value
            description.gsub!(" #{p[0]}=#{value}", " #{p[0]}=\{#{converted_value}\}")
            description.gsub!("+#{p[0]}=#{value}", "+#{p[0]}=\{#{converted_value}\}")
          end
        end
      end
    }
    return description
  end

  @@VALID_MOSFET_PARAMETERS = %w[m l w ad as pd ps nrd nrs ic temp]

  def convert_netlist orig_netlist, param_vals=nil, subckt_for_model=false
    return nil unless orig_netlist
    new_net = ''
    flag = nil  # lang=spice if true
    curly_model = nil # model is like 'model nch_x bsim4  { \n...\n  }'
    inside_subckt_flag = nil # avoid to add 'm=1' when .param used outside of subckt
    netlist, breaks = unwrap orig_netlist    # continuation w/ '+' unwrapped    
    converted_model = {}
    netlist.each_line{|l|
      if  l =~ /^model +(\w+) +(\w+)/ # model inside subckt
        if $2 == 'capacitor'
          converted_model[$1] = convert_capacitor_model l 
        elsif $2 == 'resistor'
          converted_model[$1] = convert_resistor_model l 
        end
      end
    }
    count = -1
    netlist.each_line{|l|
      count = count + 1
      wl = wrap(l, breaks[count])
      l.chomp!
      if curly_model
        curly_model << wl
        if l =~ /^ *\} *$/
          new_net << convert_model(curly_model, param_vals)  #  + "\n" maybe unnecessary
          curly_model = nil
        end
        next
      elsif l =~ /^model +(\w+) +(\w+)/ # model inside subckt
        type = $2
        if l =~ /^model .* \{ *$/
          curly_model = wl
        else
          unless type == 'capacitor' || type == 'resistor'
            new_net << convert_model_sub('.'+wl, param_vals) + "\n"
          end
        end
        next
      elsif l =~ /simulator +lang *= *spectre/
        flag = nil
        next
      elsif l =~ /simulator +lang *= *spice/
        flag = true
        next
      elsif flag
        new_net << l + "\n"
        next
      elsif l =~ /^global/
        new_net << '.' + l.sub(' 0 ',' ') + "\n"
      elsif l =~ /^parameters/
        pairs, singles = parse_parameters(l)
        @param = pairs.keys
        singles && singles.each{|s| wl.sub!(/ #{s} /, " #{s}=0 ")}
        wl = subst_values wl, l, pairs
        if subckt_for_model && inside_subckt_flag && pairs['m'].nil?
          inside_subckt_flag = nil # to avoid adding m=1 in case of multiple .param statements
          new_net << wl.sub('parameters', '.param m=1') + "\n"
        else
          new_net << wl.sub('parameters', '.param') + "\n"
        end
      elsif l =~ /^\/\//
        new_net << '*' + l[2..-1] + "\n"
      elsif l =~ /(^ *)(subckt)/ || l =~ /(^ *)(inline +subckt)/
        new_net << '.' + l.sub($2, 'subckt') + "\n"
        inside_subckt_flag = true 
      elsif l =~ /^ends/
        new_net << '.' + l + "\n"
      elsif l=~ /(^ *)([DdQq]\S*) (\([^\)]*\)) +(\S+) +(.*)$/
        parms, = parse_parameters $5
        l.sub!(/ *= */, '=')
        parms.each_pair{|k, v|
            l.sub!("#{k}=#{v}", "#{k}=#{eng(v)}")
        }
        if subckt_for_model
          if parms['area']
            l.sub! "area=#{parms['area']}", "area={#{parms['area']}*m}"
            l.sub! "area={#{parms['area']}}", "area={#{parms['area']}*m}"
          else
            l.sub! /#{$5}/, "area={m} #{$5}"
          end
        end
        l.sub!(/region *= *\S+/, '')
        new_net << new_wrap(l + "\n")
      elsif l=~ /(^ *)([Mm]\S*) (\([^\)]*\)) +(\S+) +(.*)$/ ||
          l=~ /(^ *)(\S*) (\([^\)]*\)) +(nmos\S*|pmos\S*) +(.*)$/ || # dirty hack to
          l=~ /(^ *)(\S*) (\([^\)]*\)) +(nch\S*|pch\S*) +(.*)$/      # check if this is mos
        name = $2
        l.sub! $3, parstrip($3)
        model = $4 
        parms, = parse_parameters $5
        l.sub!(/ *= */, '=')
        parms.each_pair{|k, v|
          if @@VALID_MOSFET_PARAMETERS.include? k.downcase
            l.sub!("#{k}=#{v}", "#{k}=#{eng(v)}")
          else
            l.sub!("#{k}=#{v}", '')
            puts "warning: '#{k}' has been removed because it is not a valid MOSFET instance parameter"
          end
        }
        if subckt_for_model
          if parms['m']
            l.sub! "m=#{parms['area']}", 'm={m}'
          else
            l.sub! " #{model} ", " #{model} m={m} "
          end
        end
        l.sub!(/region *= *\S+/, '')
        l.sub!(name, "M#{name}") unless name.start_with?('M')||name.start_with?('m')
        new_net << new_wrap(l + "\n")

      elsif l=~ /(^ *)(\S*) +(\(.*\)) +relay +(.*) */
        parms, = parse_parameters $4
        new_net << new_wrap("#{$1}#{prefix($2,'s')} #{parstrip $3} #{$2}\n")
        new_net << new_wrap(".model #{$2} SW roff=#{eng(parms['ropen'])} ron=#{eng(parms['rclosed'])}")
        new_net << new_wrap(" vt={(#{parms['vt1']}+#{parms['vt2']})/2} vh={(#{parms['vt1']}-#{parms['vt2']})/2}\n")
      elsif l=~ /(^ *)(\S+) +(\(.*\)) +vsource +(.*) */
        new_net << new_wrap("#{$1}#{prefix($2,'v')} #{parstrip $3} #{parse_src $4}\n")
      elsif l=~ /(^ *)(\S+) +(\(.*\)) +isource +(.*) */
        new_net << new_wrap("#{$1}#{prefix($2,'i')} #{parstrip $3} #{parse_src $4}\n")
      elsif l=~ /(^ *)(\S+) +(\(.*\)) +vcvs +(.*) */
        parms, = parse_parameters $4
        new_line = "#{$1}E#{$2} #{parstrip $3} "
        if parms['min'] && parms['max']
          new_line << "table=({#{eng(parms['min'])}/#{eng(parms['gain'])}}, {#{eng(parms['min'])}}, "
          new_line << "{#{eng(parms['max'])}/#{eng(parms['gain'])}}, {#{eng(parms['max'])}})\n"
        else
          new_line << "#{eng(parms['gain'])}\n"
        end
        new_net << new_wrap(new_line)
      elsif l=~ /(^ *)(\S+) +(\(.*\)) +vccs +gm *= *(\S+) */
        new_net << "#{$1}G#{$2} #{parstrip $3} #{eng $4}\n"
      elsif l=~ /(^ *)(\S+) +(\(.*\)) +cccs +gain *= *(\S+) +probe *= *(\S+) */
        new_net << "#{$1}F#{$2} #{$4} #{eng $3}\n"
      elsif l=~ /(^ *)(\S+) +(\(.*\)) +ccvs +rm *= *(\S+) +probe *= *(\S+) */
        new_net << "#{$1}H#{$2} #{$4} #{eng $3}\n"
      elsif l=~ /(^ *)([Ii]\S*) +(\(.*\)) +(\S+) *(.*) */
        new_net << new_wrap("#{$1}X#{$2} #{parstrip $3} #{$4} #{$5}\n")
      elsif l=~ /(^ *)(\S+) +(\(.*\)) +(\S+) +[Ll] *= *(\S+) *(.*) */
        if $4 == 'inductor'
          new_net << new_wrap("#{$1}#{prefix($2,'l')} #{parstrip $3} #{eng $5} #{rest_parms $6}\n")
        else  # not always inductor: eg. "r12 (n3 n4) rsilpp1 l=2.200e-07 w=w"
          new_net << new_wrap("#{$1}X#{$2} #{parstrip $3} #{$4} l=#{eng $5} #{rest_parms $6, subckt_for_model}\n")
        end
      elsif l=~ /(^ *)(\S+) +(\((.*)\)) +(\S+) +([CcQq]) *= *(\S+) *(.*) */
        ctype = $6.downcase
        if $5 == 'bsource'
          n1, n2 = $4.strip.split
          new_net << "#{$1}#{$2} #{n1} #{n2} "
          body = "#{$7} #{$8}".gsub(/[Vv]\(#{n1}\) *- *[Vv]\(#{n2}\)/, 'x')
          if ctype == 'c'
            new_net << "Q=(#{body}*(x)) m={m}\n"
          elsif ctype == 'q'
            new_net << "Q=#{body} m={m}\n"
          end
        elsif $5 == 'capacitor'
          if subckt_for_model
#            new_net << new_wrap("#{$1}#{prefix($2,'c')} #{parstrip $3} #{eng $7, true} #{rest_parms $8}\n") # this does not work when $7 is not sliced correctly
            new_net << new_wrap("#{$1}#{prefix($2,'c')} #{parstrip $3} #{eng $7+' '+$8} m={m}\n") # quick fix!
          else
            new_net << new_wrap("#{$1}#{prefix($2,'c')} #{parstrip $3} #{eng $7} #{rest_parms $8}\n")
          end
        else
          if subckt_for_model
            new_net << new_wrap("#{$1}X#{$2} #{parstrip $3} #{$4} c={#{eng $7}} #{rest_parms $8} m={m}\n")
          else
            new_net << new_wrap("#{$1}X#{$2} #{parstrip $3} #{$4} c=#{eng $7} #{rest_parms $8}\n")
          end
        end
      elsif l=~ /(^ *)(\S+) +(\((.*)\)) +(\S+) +[Rr] *= *(\S+) *(.*) */
        if $5 == 'bsource'
          n1, n2 = $4.strip.split
#          new_net << "#{$1}b#{$2} #{$3} i={v(#{n1},#{n2})/(#{$6} #{$7})}\n"
          new_net << new_wrap("#{$1}b#{$2} #{n1} #{n2} i={(v(#{n1},#{n2})/(#{$6} #{$7}))*m}\n")
        else
          if $5 == 'resistor'
            if subckt_for_model
              new_line = "#{$1}#{prefix($2,'r')} #{parstrip $3} #{eng $6, -1} "
            else
              new_line = "#{$1}#{prefix($2,'r')} #{parstrip $3} #{eng $6} "
            end
          else
            if subckt_for_model
              new_line = "#{$1}X#{$2} (#{$4}) #{$5} r=#{eng $6, true}"
            else
              new_line = "#{$1}X#{$2} (#{$4}) #{$5} r=#{eng $6}"
            end
          end
          rest = $7? $7.sub(/isnoisy *= \S+/, ''):nil
          new_net << new_wrap(new_line + "#{rest_parms rest}\n")
        end
      elsif l =~ /(^ *)([RrCcLl]\S*) +(\([^\)]*\)) +(\S+) +(.*)$/
        new_net << new_wrap("#{$1}X#{$2} #{parstrip $3} #{$4} #{rest_parms $5, subckt_for_model}\n")
      elsif l =~ /(^ *)([RrCcLl]\S*) +(\([^\)]*\)) +(\S+) *$/
        if converted_model[$4] # model is capacitor or resistor
          space, name, net, model = [$1, $2, parstrip($3), $4] 
          if prefix = converted_model[model]['prefix'] 
            new_net << converted_model[model]['params'] 
            vsrc = 'v' + net.gsub(/ +/, ',')
            value = converted_model[model]['value'].gsub('#{vsrc}', vsrc) 
            new_net << new_wrap("#{space}#{prefix}#{name} #{net} #{value}\n")
          else
            new_net << converted_model[model]['params'] 
            value = converted_model[model]['value'] 
            new_net << new_wrap("#{space}#{name} #{net} #{value}\n")
          end
        else
          new_net << new_wrap("#{$1}X#{$2} #{parstrip $3} #{$4}\n")
        end
      elsif l =~ /(^ *)([Xx]\w*) +([^=]*) +(\w+ *= *.*$)/
        new_net << new_wrap("#{$1}#{$2} #{parstrip $3} #{rest_parms $4, subckt_for_model}\n")
      else
        new_net << new_wrap(l+"\n")
      end
    }
    new_net
  end

  def prefix s, p
    (s.start_with?(p) || s.start_with?(p.upcase))? s : p.upcase+s
  end

  def convert_capacitor_model l
    # model name capacitor c=.. tc1=.. tc2=..
    mp, = parse_parameters l 
    result = ''
    tc1 = mp['tc1'] || 0
    tc2 = mp['tc2'] || 0
#    m = mp['m'] || 1
    result << ".param tnom=27 tc1=#{tc1} tc2=#{tc2}\n"
    if c = mp['c']
      result << "+ ctemp={#{c}*(1+tc1*(temp-tnom)+tc2*(temp-tnom)**2)*m}\n"
    else
      result << "+ w=0 l=0 etch=0 cj=0 cjsw=0\n"
      result << "+ area_eff={(l - 2*etch)*w - 2*etch}\n"
      result << "+ perim_eff={2 *w + l - 4*etch}\n"
      result << "+ ctemp={cj*area_eff + cjsw*perim_eff}\n"
      result << "+ *(1+tc1*(temp-tnom)+tc2*(temp-tnom)**2)*m}\n"
    end
    if mp['coeffs']
      result << '+'
      coeffs = mp['coeffs'][1..-2].split
      vincr = coeffs.each_with_index.map{|c, i|
        result << " c#{i+1}=#{c}"
        exp = "**#{i+1}" if i > 0
        "(1/#{i+2})*c#{i+1}*x#{exp}"
      }.join('+') 
      {'params' => result + "\n", 'value' => "q=ctemp*x*(1+#{vincr})"}
    else
      {'params' => result, 'value' => '{ctemp}'}
    end
  end

  def convert_resistor_model l
    # model name resistor r=.. tc1=.. tc2=..
    mp, = parse_parameters l 
    result = ''
    tc1 = mp['tc1'] || 0
    tc2 = mp['tc2'] || 0
#    m = mp['m'] || 1
    result << ".param tnom=27 tc1=#{tc1} tc2=#{tc2}\n"
    unless r = mp['r']
      result << "+ rsh=0 l=0 w=0 etch=0 etchl=0\n"
      result << "+ r={rsh * (l - 2*etchl) / (w - 2*etch)}\n"
    end
    result << "+ rtemp={r*(1+tc1*(temp-tnom)+tc2*(temp-tnom)**2)}\n"
    if mp['coeffs']
      result << '+'
      coeffs = mp['coeffs'][1..-2].split
      vincr = coeffs.each_with_index.map{|c, i|
        result << " c#{i+1}=#{c}"
        exp = "**#{i+1}" if i > 0
        "(1/#{i+2})*c#{i+1}*\#\{vsrc\}#{exp}"
      }.join('+') 
      {'params' => result + "\n", 'value' => "i=(#\{vsrc\}/rtemp)*(1+#{vincr})*m", 'prefix' => 'B'}
    else
      {'params' => result, 'value' => '{rtemp/m}'}
    end
  end

  class LTspiceNodes
    attr_accessor :map
    def initialize
      @map = {}
    end
    def set n
      if n.downcase =~ /(\S+):p/
        m = "I(#{$1.upcase})"
      elsif n.downcase =~ /(\S+):(\S+)/
        e = $1.downcase
        node = $2
        if node == 'sink'
          m = "I(#{e.capitalize})"
        else
          case e[0..0]
          when 'q'
            node = ['C', 'B', 'E', 'S'][node.to_i-1]
            m = "Ix(#{e}:#{node})"
          when 'm'
            node = ['D', 'G', 'S', 'B'][node.to_i-1]
            m = "Ix(#{e}:#{node})"
          else
            m = "Ix(#{e}:N#{node})"
          end
        end
      else
        m = "V(#{n.downcase})"
      end
      @map[n] = m
    end
    def get n
      @map[n]
    end
  end
  
  def convert_postprocess postprocess
    return nil unless postprocess
    new_pp = ''
    type = nil
    conv = LTspiceNodes.new
    postprocess.each_line{|l|
      l.chomp!
      if l =~ /^ *(\S+) *: *(\S+)\.(\S+)/
        new_pp << "#{$1.sub('Spectre_', '')}:#{$3}\n"
        type = $3
      elsif l =~ /(^.*)@spectre.get_psf +(\S+), +(\S+), +(\S+), +(.*)/
#       @spectre.get_psf 'tran.csv', 'tran.tran', 'time', 'in', 'out'
	lhs = $1
        csv = $2
        sweep = $4
        nodes = $5.gsub("'",'').gsub(' ','').split(',') # nodes are downcase in LTspice --- should be revised in the future
        if type == 'noise'
          new_pp << "#{lhs}@ltspice.save #{csv}, '#{type}', 'frequency', 'V(inoise)', 'V(onoise)'\n"
        elsif sweep == "'freq'"
#          new_pp << "#{lhs}@ltspice.gain #{csv}, #{nodes.map{|a| "'V(#{a})'"}.join(', ')}\n"
          new_pp << "#{lhs}@ltspice.save #{csv}, '#{type}', 'frequency',#{nodes.map{|a| "'#{conv.set a}'"}.join(', ')}\n"
        elsif sweep == "'dc'"
          if @dc_sweep
            new_pp << "#{lhs}@ltspice.save #{csv}, '#{type}', '#{@dc_sweep.sub('temp', 'temperature')}', #{nodes.map{|a| conv.set a}.join(', ')}\n"
          else
            new_pp << "#{lhs}@ltspice.save #{csv}, '#{type}', '*conversion failed*', #{nodes.map{|a| "'V(#{a})'"}.join(', ')}\n"
          end
        else # tran and the rest
          new_pp << "#{lhs}@ltspice.save #{csv}, '#{type}', #{sweep}, #{nodes.map{|a| "'#{conv.set a}'"}.join(', ')}\n"
        end
      else
        new_pp << l + "\n"
      end
    }
    conv.map.each{|a, b|
      new_pp.gsub! "'#{a}'", "'#{b}'" 
    }
    new_pp
  end
          
  def convert_control orig_control
    return nil unless orig_control
    new_control = ''
    flag = nil  # lang=spice if true    
    control, breaks = unwrap orig_control    # continuation w/ '+' unwrapped    
#    control.gsub(/\\\r*\n/, '').each_line{|l|      
    control.each_line{|l|      
      l.chomp!
      if l =~ /simulator +lang *= *spectre/
        flag = nil
        next
      elsif l =~ /simulator +lang *= *spice/
        flag = true
        next
      elsif flag
        new_control << l + "\n"
        next
      elsif l =~ /^([^ ]+) +dc +dev=([^ ]+) +param=([^ ]+) +(.*)/
        @dc_sweep = $2.downcase # dc sweep voltage name in output is lowercase
        new_control << ".dc #{$2} #{parse_dc_sweep $4}\n"
      elsif l =~ /^([^ ]+) +dc +param=([^ ]+) +(.*)/
        new_control << ".dc #{$2} #{parse_dc_sweep $3}\n"
      elsif l =~ /^([^ ]+) +dc /
        new_control << ".op\n"
      elsif l =~ /^([^ ]+) +ac +(.+)/
        new_control << ".ac #{parse_ac_sweep $2}\n"
      elsif l =~ /^(\w+) +tran +stop= *([^ ]+)/
        new_control << ".tran #{$2}\n"
      elsif l =~ /^noise +\((.*)\) +(\w+) +(.*) +iprobe=(\w+)/
        new_control << ".noise V(#{$1}) #{$4} #{parse_ac_sweep $3}\n"
#      elsif l =~ /^op/
#        new_control << ".op\n"
      elsif l =~ /^global/
        new_control << '.' + l.sub(' 0 ',' ') + "\n"
      elsif l =~ /^parameters/
        params, = parse_parameters l
        subst = {}
        params.each_pair{|p, v|
          next if numeric? v
          next unless eng? v
          if v=~/[0-9]M/
            subst[p] = v.sub $&, $&[0..0]+'MEG'
          end
        }
        l.sub! " *= *'", '='
        subst.each_pair{|p, v|
          l.sub! "#{p}=#{params[p]}", "#{p}=#{v}"
        }
        new_control << l.sub('parameters', '.param') + "\n"
      elsif l =~/^\S+ options +(.*)/
        opts = parse_options $1
        new_control << ".options#{opts}\n" if opts && opts!=''
      end
    }
    new_control
  end

  def eng? val
    val =~/^([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?) *[fpnumKMGT]*$/
  end
  private :eng?

  def parstrip nets
    if @@parenthesis_strip
      nets.gsub /[\(\)]/,''
    else
      nets
    end
  end
  private :parstrip
end

def wrap line, breaks
  return line if breaks.size == 0
  line_copy = line.dup
#  puts "#{line}:#{breaks.inspect}"
  breaks.reverse_each{|pos|
    if pos>0
      line_copy[pos..pos] = "\n+" + line_copy[pos..pos]  # insert
    else
      line_copy[-pos..-pos] = "\\\n"    # just replace 
    end
  }
  line_copy
end

def parse_model description
  params = {}
  return params unless description
#  return params unless a.include?('.model')||a.include?('.param')

  if description =~ /\.(param|PARAM)/
    if description =~ /\.(model|MODEL)/
      a = ''
      flag = nil
      description.each_line{|l|
        if flag || (l =~ /^ *\.(model|MODEL)/)  # ignore .param description in front of .model
          flag = true
          a << l
        end
      }
    else
      a = description.dup
    end
  else  # what is this case? model having .param only?
    a = description.dup.chomp
  end
  return params unless a =~ /\.(model|param|MODEL|PARAM)/
  a.gsub!(/^\*.*\n/,'') # remove comment lines
  a.gsub!(/\t/,'')      # remove tabs
 if a =~ /^.*\.(model|MODEL) +\S+ +\S+ *\(/ # remove the unnecessary '('
    a.sub! /\)[^\)]*$/, "\n"           # remove the matching ') at the end'
    a.gsub!(/^.*\.(model|MODEL) +(\S+) +(\S+) *\(/,' ')
  else
    a.gsub!(/^.*\.(model|MODEL) +(\S+) +(\S+) */,' ')  # ' ' should not be '' otherwise \ntype appears
  end
  name = $2
  type = $3
#  a.gsub(/\n *\+/,' ').scan(/([^ =]+) *= *(\'[^\']*\'|\S+)/).each{|pair|
#    params[pair[0]] = pair[1]
#  }
  params, = parse_parameters a.gsub(/\n *\+/,' ')
#if @debug == nil
#  debugger
#end
=begin  
  if type == 'bjt'
    type = params['type']
  end
  if type == 'pnp'
    if params['struct'] 
      type = 'vpnp' if params['struct'] == 'vertical'
      type = 'lpnp' if params['struct'] == 'lateral'
    elsif params['subs']
      type = 'lpnp' if params['subs'].to_i == -1
      type = 'vpnp' if params['subs'].to_i == 1
    end
  end
=end
  return [type, name, params]
end

def parse_parameters line
  start = Time.now
  params = {}
  singles = []
  return [params, singles] if line.nil?
  line2 = line.strip.dup
  pa = nil
  count = 0
  while line2.size > 0 && count < 10000
    count = count + 1
    if line2 =~ /^( *([^ =]+) +)[^ =]/
      singles << $2
      line2.sub! $1, ''
#    elsif line2 =~ /^( *([^ =><]+) *= *)/
    elsif line2 =~ /^( *(\w+) *= *)/
      pa = $2.strip
      line2.sub! $1, ''
#      i = (line2 =~ /( +([^ =\)\(><]+) *=[^=] *)/) || -1
      i = (line2 =~ /( +(\w+) *=[^=] *)/) || -1
      v = line2[0..i]
      line2[0..i] = ''
      params[pa] = v.strip if v
    elsif line2 =~ /^( *(\S+) *)$/
      singles << $2
      line2.sub! $1, ''
    end
    puts "!!! #{count}:#{line2}" if count == 10000
  end
=begin
  puts "singles: #{singles.inspect}"
  puts "params: #{params.inspect}"
  puts "Elapse: #{Time.new - start}"
=end
  [params, singles]
end

description = File.read(ARGV[0])
if ARGV[1]
  raise "Error: #{ARGV[1]} does not exist!" unless File.exist? ARGV[1]
  spice_default_parameters = []
  File.read(ARGV[1]).each_line{|l|
    l.chomp!
    spice_default_parameters << l.split(/[ ,=]/)
  }
else
  spice_default_parameters = [["GMIN", 1e-12], ["PS", 1.2e-05], ["PD", 1.2e-05], ["AS", 1.2e-11], ["AD", 1.2e-11], ["CGBO", -99], ["CGDO", -99], ["CGSO", -99], ["L", 3e-06], ["W", 6e-06], ["MOBMOD", -99], ["RDSMOD", -99], ["IGCMOD", 0], ["IGBMOD", 0], ["CAPMOD", 2], ["RGATEMOD", 2], ["RBODYMOD", 0], ["DIOMOD", 1], ["TEMPMOD", -99], ["GEOMOD", 0], ["RGEOMOD", 0], ["PERMOD", 1], ["TNOIMOD", 0], ["FNOIMOD", 0], ["EPSROX", 3.9], ["TOXE", -99], ["TOXP", -99], ["TOXM", -99], ["DTOX", 0], ["XJ", 1.5e-07], ["GAMMA1", -99], ["GAMMA2", -99], ["NDEP", -99], ["NSUB", 6e+16], ["NGATE", 0], ["NSD", 1e+20], ["VBX", -99], ["XT", 1.55e-07], ["RSH", 0], ["RSHG", 0], ["VTH0", 0.6], ["VFB", -99], ["PHIN", 0], ["K1", -99], ["K2", -99], ["K3", 80], ["K3B", 0], ["W0", 2.5e-06], ["LPE0", 1.74e-07], ["LPEB", 0], ["VBM", -3], ["DVT0", 2.2], ["DVT1", 0.53], ["DVT2", -0.032], ["DVTP0", 0], ["DVTP1", 0], ["DVT0W", 0], ["DVT1W", 5.3e+06], ["DVT2W", -0.032], ["U0", -99], ["UA", -99], ["UB", 1e-19], ["UC", -99], ["EU", -99], ["VSAT", 80000], ["A0", 1], ["AGS", 0], ["B0", 0], ["B1", 0], ["KETA", -0.047], ["A1", 0], ["A2", 1], ["WINT", 0], ["LINT", 0], ["DWG", 0], ["DWB", 0], ["VOFF", -0.08], ["VOFFL", 0], ["MINV", 0], ["NFACTOR", 1], ["ETA0", 0.08], ["ETAB", -0.07], ["DROUT", 0.56], ["DSUB", 0.56], ["CIT", 0], ["CDSC", 0.00024], ["CDSCB", 0], ["CDSCD", 0], ["PCLM", 1.3], ["PDIBL1", 0.39], ["PDIBL2", 0.0086], ["PDIBLB", 0], ["PSCBE1", 4.24e+08], ["PSCBE2", 1e-05], ["PVAG", 0], ["DELTA", 0.01], ["FPROUT", 0], ["PDITS", 0], ["PDITSD", 0], ["PDITSL", 0], ["LAMBDA", -99], ["VTL", -99], ["LC", 5e-09], ["XN", 3], ["RDSW", 200], ["RDSWMIN", 0], ["RDW", 100], ["RDWMIN", 0], ["RSW", 100], ["RSWMIN", 0], ["PRWG", 1], ["PRWB", 0], ["WR", 1], ["NRS", -99], ["NRD", -99], ["ALPHA0", 0], ["ALPHA1", 0], ["BETA0", 30], ["AGIDL", 0], ["BGIDL", 2.3e+09], ["CGIDL", 0.5], ["EGIDL", 0.8], ["AIGBACC", 0.43], ["BIGBACC", 0.054], ["CIGBACC", 0.075], ["NIGBACC", 1], ["AIGBINV", 0.35], ["BIGBINV", 0.03], ["CIGBINV", 0.006], ["EIGBINV", 1.1], ["NIGBINV", 3], ["AIGC", -99], ["BIGC", -99], ["CIGC", -99], ["AIGSD", -99], ["BIGSD", -99], ["CIGSD", -99], ["DLCIG", 0], ["NIGC", 1], ["POXEDGE", 1], ["PIGCD", 1], ["NTOX", 1], ["TOXREF", 3e-09], ["XPART", 0.4], ["CGS0", 0], ["CGD0", 0], ["CGB0", 0], ["CGSL", 0], ["CGDL", 0], ["CKAPPAS", 0.6], ["CKAPPAD", 0.6], ["CF", -99], ["CLC", 1e-07], ["CLE", 0.6], ["DLC", 0], ["DWC", 0], ["VFBCV", -1], ["NOFF", 1], ["VOFFCV", 0], ["ACDE", 1], ["MOIN", 15], ["XRCRG1", 12], ["XRCRG2", 1], ["RBPB", 50], ["RBPD", 50], ["RBPS", 50], ["RBDB", 50], ["RBSB", 50], ["GBMIN", 1e-12], ["DMCG", 0], ["DMCI", 0], ["DMDG", 0], ["DMCGT", 0], ["NF", 1], ["DWJ", 0], ["MIN", 0], ["XGW", 0], ["XGL", 0], ["XL", 0], ["XW", 0], ["NGCON", 1], ["IJTHSREV", 0.1], ["IJTHDREV", 0.1], ["IJTHSFWD", 0.1], ["IJTHDFWD", 0.1], ["XJBVS", 1], ["XJBVD", 1], ["BVS", 10], ["BVD", 10], ["JSS", 0.0001], ["JSD", 0.0001], ["JSWS", 0], ["JSWD", 0], ["JSWGS", 0], ["JSWGD", 0], ["CJS", 0.0005], ["CJD", 0.0005], ["MJS", 0.5], ["MJD", 0.5], ["MJSWS", 0.33], ["MJSWD", 0.33], ["CJSWS", 5e-10], ["CJSWD", 5e-10], ["CJSWGS", 5e-10], ["CJSWGD", 5e-10], ["MJSWGS", 0.33], ["MJSWGD", 0.33], ["PBS", 1], ["PBD", 1], ["PBSWS", 1], ["PBSWD", 1], ["PBSWGS", 1], ["PBSWGD", 1], ["TNOM", 27], ["UTE", -1.5], ["KT1", -0.11], ["KT1L", 0], ["KT2", 0.022], ["UA1", 1e-09], ["UB1", -1e-18], ["UC1", -99], ["AT", 33000], ["PRT", 0], ["NJS", 1], ["NJD", 1], ["XTIS", 3], ["XTID", 3], ["TPB", 0], ["TPBSW", 0], ["TPBSWG", 0], ["TCJ", 0], ["TCJSW", 0], ["TCJSWG", 0], ["SA", 0], ["SB", 0], ["SD", 0], ["SAREF", 1e-06], ["SBREF", 1e-06], ["WLOD", 0], ["KU0", 0], ["KVSAT", 0], ["TKU0", 0], ["LKU0", 0], ["WKU0", 0], ["PKU0", 0], ["LLODKU0", 0], ["WLODKU0", 0], ["KVTH0", 0], ["LKVTH0", 0], ["WKVTH0", 0], ["PKVTH0", 0], ["LLODVTH", 0], ["WLODVTH", 0], ["STK2", 0], ["LODK2", 1], ["STETA0", 0], ["LODETA0", 1], ["WL", 0], ["WLN", 1], ["WW", 0], ["WWN", 1], ["WWL", 0], ["LL", 0], ["LLN", 1], ["LW", 0], ["LWN", 1], ["LWL", 0], ["LLC", 0], ["LWC", 0], ["LWLC", 0], ["WLC", 0], ["WWC", 0], ["WWLC", 0], ["NTNOI", 1], ["KF", 0], ["AF", 1], ["EF", 1], ["TEMP", 27]]
end

converter = Spectre_to_LTspice.new spice_default_parameters
result = converter.convert_model description
puts result
