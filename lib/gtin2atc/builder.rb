require 'csv'
require 'rubyXL'
require "gtin2atc/options"
require "gtin2atc/downloader"
require "gtin2atc/xml_definitions"
require 'mechanize'
require 'open-uri'

module Gtin2atc
  class Builder
    Strip_For_Sax_Machine = '<?xml version="1.0" encoding="utf-8"?>'+"\n"
    SameInAll             = 'atc where the same in bag, swissindex and swissmedic'
    AtcNotInSwissindex    = 'atc not in swissindex'
    AtcNotInSwissmedic    = 'atc not in swissmedic'
    AtcNotInBag           = 'atc not in bag'
    AtcDifferent          = 'atc differed'
    CsvOutputOptions      =  { :col_sep => ';', :encoding => 'UTF-8'}
    Mesurements = [ 'g', 'kg', 'l', 'mg', 'ml', 'cm', 'GBq']
    # see  Selection of units of WHO DDD guidelines
    RouteOfAdministrations = ['Inhal', 'R', 'N', 'O', 'SL', 'P', 'V', 'TD']

    def initialize(opts)
      Util.set_logging(opts[:log])
      @output = opts[:output]
      @do_compare = opts[:compare]
      @gen_reports = opts[:compare] and opts[:full]
      Util.debug_msg "Builder: opts are #{opts} @do_compare is #{@do_compare} output #{@output}"
      @data_swissmedic = {}
      @data_bag = {}
      @data_swissindex = {}
      @bag_entries_without_gtin = 0
    end
    def calc_checksum(str)
      str = str.strip
      sum = 0
      val =   str.split(//u)
      12.times do |idx|
        fct = ((idx%2)*2)+1
        sum += fct*val[idx].to_i
      end
      ((10-(sum%10))%10).to_s
    end
    def epha_atc_extractor
      data = {}
      body = open('https://download.epha.ch/data/atc/atc.csv').read.force_encoding('UTF-8')
      Util.debug_msg "epha_atc_extractor is #{body.size} bytes long"
      csv = CSV.new(body, { :headers => false, :col_sep => ',' } )
      csv.to_a.each{
        |line|
        data[line[0]] = line[2] if line[2]
      }
      Util.debug_msg "epha_atc_extractor extracted #{data.size} items"
      data
    end
    def swissmedic_xls_extractor
      @swissmedic = SwissmedicDownloader.new
      filename = @swissmedic.download
      Util.debug_msg "swissmedic_xls_extractor xml is #{filename}"
      data = {}
      @sheet = RubyXL::Parser.parse(File.expand_path(filename)).worksheets[0]
      i_5,i_3   = 0,10 # :swissmedic_numbers
      atc       = 5    # :atc_code
      @sheet.each_with_index do |row, i|
        next if (i <= 1)
        next unless row[i_5] and row[i_3]
        no8 = sprintf('%05d',row[i_5].value.to_i) + sprintf('%03d',row[i_3].value.to_i)
        unless no8.empty?
          next if no8.to_i == 0
          item = {}
          ean_base12 = "7680#{no8}"
          gtin = (ean_base12.ljust(12, '0') + calc_checksum(ean_base12)).to_i
          item = {}
          item[:gtin]            = gtin
          item[:atc_code]         =  row[atc] ? row[atc].value.to_s : ''
          item[:name]             =  row[2].value.to_s
          data[gtin] = item
        end
      end
      Util.debug_msg "swissmedic_xls_extractor extracted #{data.size} items"
      data
    end
    def swissindex_xml_extractor
      @swissindex = SwissindexDownloader.new
      xml = @swissindex.download
      Util.debug_msg "swissindex_xml_extractor xml is #{xml.size} bytes long"
      data = {}
      result = PharmaEntry.parse(xml.sub(Strip_For_Sax_Machine, ''), :lazy => true)
      items = result.PHARMA.ITEM
      items.each do |pac|
        item = {}
        gtin = pac.GTIN ? pac.GTIN.to_i : nil
        next unless item[:gtin].to_i
        item[:gtin]            = gtin
        item[:pharmacode]      = (phar = pac.PHAR)   ? phar: ''
        item[:atc_code]        = (code = pac.ATC)    ? code.to_s : ''
        item[:description]     = pac.DSCR
        data[gtin] = item
      end
      Util.debug_msg "swissindex_xml_extractor extracted #{data.size} items"
      data
    end
    def oddb_calc_xml_extractor
      filename = 'oddb_calc.xml'
      data = {}
      unless File.exists?('oddb_calc.xml')
        puts "Unable to open #{filename}"
      else
        xml = IO.read(filename)
        Util.debug_msg "oddb_calc_xml_extractor xml is #{xml.size} bytes long"
        result = ARTICLESEntry.parse(xml.sub(Strip_For_Sax_Machine, ''), :lazy => true)
        result.ARTICLES.ARTICLE.each do |article|
          item = {}
          gtin = article.GTIN.to_i
          item[:gtin]            = gtin
          item[:PKG_SIZE]        = article.PKG_SIZE
          item[:SELLING_UNITS]   = article.SELLING_UNITS
          item[:MEASURE]         = article.MEASURE
          if article.COMPOSITIONS.COMPONENT and article.COMPOSITIONS.COMPONENT.size == 1
            item[:COMPOSITIONS]    = article.COMPOSITIONS
          end
          data[gtin]     = item
        end
        Util.debug_msg "oddb_calc_xml_extractor extracted #{data.size} items"
      end
      data
    end
    def bag_xml_extractor
      data = {}
      @bag = BagDownloader.new
      xml = @bag.download
      Util.debug_msg "bag_xml_extractor xml is #{xml.size} bytes long"

      result = PreparationsEntry.parse(xml.sub(Strip_For_Sax_Machine, ''), :lazy => true)
      @bag_entries_without_gtin = 0
      result.Preparations.Preparation.each do |seq|
        item = {}
        item[:atc_code]     = (atcc = seq.AtcCode)       ? atcc : ''
        seq.Packs.Pack.each do |pac|
          gtin = pac.GTIN
          if gtin
            gtin = gtin.to_i
            item[:gtin] = gtin
            item[:name] = seq.NameDe + " " +  pac.DescriptionDe
            if pac.Prices
              item[:exfactory_price] = pac.Prices.ExFactoryPrice.Price if pac.Prices.ExFactoryPrice
              item[:public_price]    = pac.Prices.PublicPrice.Price if pac.Prices.PublicPrice
            end
            data[gtin] = item
            Util.debug_msg "run_bag_extractor add #{item}" if $VERBOSE
          else
            @bag_entries_without_gtin += 1
            Util.debug_msg "run_bag_extractor skip phar #{seq.NameDe}: #{seq.DescriptionDe} without gtin."
          end
        end
      end
      Util.debug_msg "bag_xml_extractor extracted #{data.size} items. Skipped #{@bag_entries_without_gtin} entries without gtin"
      data
    end

    # return [qty, unit, roa] for simple, valid ddd
    # return [nil, nil, full_text] for structured DDDs like Standarddosis: 10 Tabletten oder 50 ml Mixtur
    # a simple ddd is valid if meets the following three criteria
    # first part is a float value
    # second part is a unit e.g. ml
    # third part is one or several (separated by ',') RouteOfAdministrations
    def get_valid_ddd(full_text)
      result =[nil, nil, full_text]
      return result unless full_text
      return result if full_text.index(';') # e.g. 0,12 g O,R; 18 mg P; 60 mg SL; 3 mg TD; 50 mg TD Gel; 12 mg P bezogen auf Testosteronundecanoat
      return result if full_text.index(':') # e.g. Standarddosis: 10 Tabletten oder 50 ml Mixture
      if full_text
        parts = full_text.split(' ')
        return result if parts.size > 3
        qty = parts[0] ? parts[0].sub(',', '.').to_f : ''
        if Mesurements.index(parts[1]) and qty != 0.0
          roas = parts[2].split(',')
          valid = roas.size > 0
          roas.each{
            |roa|
            unless RouteOfAdministrations.index(roa)
              valid = false
              break
            end
          }
          result =  [qty, parts[1], parts[2]] if valid
        end
      end
      result
    end

    def run(gtins_to_parse=[], output_name=nil)
      Util.debug_msg("run #{gtins_to_parse}")
      Util.debug_msg("@use_swissindex true")
      @oddb_calc = oddb_calc_xml_extractor
      @data_epha_atc = epha_atc_extractor
      @data_swissindex = swissindex_xml_extractor
      @data_bag = bag_xml_extractor
      emitted_ids = []
      if @do_compare
        output_name =  File.join(Util.get_archive, 'gtin2atc_swissindex.csv')
      else
        output_name ||= 'gtin2atc.csv'
        output_name =  File.join(Util.get_archive, output_name)
      end
      CSV.open(output_name,'w+', CsvOutputOptions) do |csvfile|
        csvfile << ["gtin", "ATC", 'pharmacode', 'description', 'exfactory_price', 'public_price', 'selling units', 'name', 'qty', 'unit', 'ddd:qty', 'ddd:unit', 'ddd:full_text']
        @data_swissindex.sort.each do |gtin, item|
          if @do_compare or gtins_to_parse.size == 0 or
            gtins_to_parse.index(gtin.to_s) or
            gtins_to_parse.index(item[:pharmacode].to_s)
            atc = item[:atc_code]
            ddd = get_valid_ddd(@data_epha_atc[atc])
            selling_units = @oddb_calc[gtin] ? @oddb_calc[gtin][:SELLING_UNITS] : nil
            exfactory_price = @data_bag[gtin] ? @data_bag[gtin][:exfactory_price] : nil
            public_price    = @data_bag[gtin] ? @data_bag[gtin][:public_price] : nil
            emitted_ids << gtin.to_i if gtin
            emitted_ids << item[:pharmacode].to_i if item[:pharmacode]
            if @oddb_calc[gtin] and @oddb_calc[gtin][:COMPOSITIONS]
              comp = @oddb_calc[gtin][:COMPOSITIONS].COMPONENT.first
              csvfile << [gtin, atc, item[:pharmacode], item[:description], exfactory_price, public_price, selling_units, comp.NAME, comp.QTY, comp.UNIT, ddd].flatten
            else
              csvfile << [gtin, atc, item[:pharmacode], item[:description], exfactory_price, public_price, selling_units, nil, nil, nil,  ddd].flatten
            end
          end
        end
      end
      msg = "swissindex: Extracted #{gtins_to_parse.size} of #{@data_swissindex.size} items into #{output_name} for #{gtins_to_parse}"
      Util.debug_msg(msg)
      missing_ids = []
      gtins_to_parse.each{
        |id|
          next if emitted_ids.index(id.to_i)
          missing_ids << id
      }
      File.open('pharmacode_gtin_not_found.txt', 'w+', CsvOutputOptions) { |f| f.write missing_ids.join("\n") }
      msg = "swissindex: Could not find info for #{missing_ids.size} missing ids see file pharmacode_gtin_not_found.txt"
      Util.debug_msg(msg)
      return unless @do_compare
      output_name =  File.join(Util.get_archive, 'gtin2atc_bag.csv')
      CSV.open(output_name,'w+', CsvOutputOptions) do |csvfile|
        csvfile << ["gtin", "ATC", 'description']
        @data_bag.sort.each do |gtin, item|
          csvfile << [gtin, item[:atc_code], item[:description]]
        end
      end
      Util.debug_msg "bag: Extracted #{gtins_to_parse.size} of #{@data_bag.size} items into #{output_name} for #{gtins_to_parse}"
      @data_swissmedic = swissmedic_xls_extractor
      output_name =  File.join(Util.get_archive, 'gtin2atc_swissmedic.csv')
      CSV.open(output_name,'w+', CsvOutputOptions) do |csvfile|
        csvfile << ["gtin", "ATC", 'description']
        @data_swissmedic.sort.each do |gtin, item|
          csvfile << [gtin, item[:atc_code], item[:pharmacode], item[:description]]
        end
      end
      Util.debug_msg "swissmedic: Extracted #{@data_swissmedic.size} items into #{output_name}"
      check_bag
      check_swissmedic
      compare
    end
    def check_bag
      matching_atc_codes = []

      not_in_swissmedic = []
      match_in_swissmedic = []
      shorter_in_swissmedic = []
      longer_in_swissmedic = []
      different_atc_in_swissmedic = []

      not_in_swissindex = []
      match_in_swissindex = []
      shorter_in_swissindex = []
      longer_in_swissindex = []
      different_atc_in_swissindex = []
      j = 0
      @data_bag.each{
        |gtin, item|
        atc_code = item[:atc_code]
        j += 1
        Util.debug_msg "#{gtin}: j #{j} checking #{atc_code} in #{item}"
        if @data_swissmedic[gtin] and @data_swissindex[gtin] and
          atc_code == @data_swissmedic[gtin][:atc_code] and
          atc_code == @data_swissindex[gtin][:atc_code]
          matching_atc_codes << "#{gtin}: matching_atc_codes swissindex #{item} #{@data_swissmedic[gtin][:atc_code]} and #{@data_swissindex[gtin][:atc_code]}"
          next
        end

        if not @data_swissindex[gtin]
          not_in_swissindex << "#{gtin}: Not in swissindex #{item}"
        elsif atc_code == @data_swissindex[gtin][:atc_code]
          match_in_swissindex << "ATC code #{atc_code} for #{gtin} matches swissindex  #{@data_swissindex[gtin][:atc_code]}"
        elsif atc_code.length < @data_swissindex[gtin][:atc_code].length
          longer_in_swissindex << "ATC code #{item[:atc_code]} for #{gtin} longer in swissindex  #{@data_swissindex[gtin][:atc_code]}"
        elsif atc_code.length > @data_swissindex[gtin][:atc_code].length
          shorter_in_swissindex << "ATC code #{atc_code} for #{gtin} shorter in swissindex  #{@data_swissindex[gtin][:atc_code]}"
        else
          matching_atc_codes << "ATC code #{atc_code} for #{gtin} differs from swissindex  #{@data_swissindex[gtin][:atc_code]}"
        end

        if not @data_swissmedic[gtin]
          not_in_swissmedic <<  "#{gtin}: Not in swissmedic #{item}"
        elsif atc_code == @data_swissmedic[gtin][:atc_code]
          match_in_swissmedic << "ATC code #{atc_code} for #{gtin} matches swissmedic  #{@data_swissmedic[gtin][:atc_code]}"
        elsif atc_code.length < @data_swissmedic[gtin][:atc_code].length
          longer_in_swissmedic << "ATC code #{item[:atc_code]} for #{gtin} longer in swissmedic  #{@data_swissmedic[gtin][:atc_code]}"
        elsif atc_code.length > @data_swissmedic[gtin][:atc_code].length
          shorter_in_swissmedic << "ATC code #{atc_code} for #{gtin} shorter in swissmedic  #{@data_swissmedic[gtin][:atc_code]}"
        else
          different_atc_in_swissmedic << "ATC code #{atc_code} for #{gtin} differs from swissmedic  #{@data_swissmedic[gtin][:atc_code]}"
        end
        total1 = not_in_swissindex + match_in_swissindex + longer_in_swissindex +  shorter_in_swissindex + different_atc_in_swissindex
        total2 = not_in_swissmedic + match_in_swissmedic + longer_in_swissmedic +  shorter_in_swissmedic + different_atc_in_swissmedic
        # Util.debug_msg "#{gtin}: j #{j} finished #{total1} #{total2} #{atc_code} matching_atc_codes #{matching_atc_codes}"
      }
      Util.info  "Result of verifing data from bag (SL):
  bag-data fetched from #{@bag.origin}.
  bag had #{@data_bag.size} entries
  #{@bag_entries_without_gtin.size} entries had no GTIN field
  Not in swissmedic #{not_in_swissmedic.size}
  Not in swissindex #{not_in_swissindex.size}
"
      Util.info "Comparing ATC-Codes between bag and swissmedic"
      topic_swissmedic = 'compare_bag_to_swissmedic'
      report(topic_swissmedic, SameInAll, matching_atc_codes)
      report(topic_swissmedic, 'atc are the same in swissmedic and bag, but not in swissindex', match_in_swissmedic)
      report(topic_swissmedic, 'atc are different in swissmedic and bag', different_atc_in_swissmedic)
      report(topic_swissmedic, 'atc are shorter in swissmedic than in bag', shorter_in_swissmedic)
      report(topic_swissmedic, 'atc are longer in swissmedic than in bag', longer_in_swissmedic)

      Util.info "Comparing ATC-Codes between bag and swissindex"
      topic_swissindex = 'compare_bag_to_swissindex'
      report(topic_swissindex, SameInAll, matching_atc_codes)
      report(topic_swissindex, 'atc are the same in swissindex and bag, but not in swissmedic', match_in_swissindex)
      report(topic_swissindex, 'atc are different in swissmedic and bag', different_atc_in_swissindex)
      report(topic_swissindex, 'atc are shorter in swissindex than in bag', shorter_in_swissindex)
      report(topic_swissindex, 'atc are longer in swissindex than in bag', longer_in_swissindex)
    end

    def report(topic, msg, details)
      full_msg = "#{topic}: #{details.size} #{msg}"
      Util.info "   #{full_msg}"
      return unless @gen_reports
      File.open((full_msg+'.txt').gsub(/[: ,]+/, '_'), 'w+') {
        |file|
        file.puts full_msg
        details.sort.each{|detail| file.puts detail }
      }
    end
    def check_swissmedic
      matching = []
      not_in_bag = []
      not_in_swissindex = []
      matching_atc_codes = []
      shorter_in_swissmedic = []
      longer_in_swissindex = []
      different_atc = []
      @data_swissmedic.each{
        |gtin, item|
        atc_code = item[:atc_code]
        if @data_bag[gtin] and
          @data_swissmedic[gtin] and
          @data_bag[gtin] and
          atc_code.eql?(@data_bag[gtin][1]) and
          atc_code.eql?(@data_swissindex[gtin][1])
          matching << "#{gtin} #{atc_code} #{@data_swissmedic[gtin][1]} match in bag, swissmedic and swissindex"
          next
        end
        unless @data_swissindex[gtin]
          not_in_swissindex << "Swissmedic #{gtin}: Not in swissindex #{item}"
          next
        end
        if item[:atc_code] == @data_swissindex[gtin][:atc_code]
          matching_atc_codes << "ATC code #{atc_code} for #{gtin} matches swissindex  #{@data_swissindex[gtin][:atc_code]}"
        elsif item[:atc_code].length < @data_swissindex[gtin][:atc_code].length
          longer_in_swissindex << "ATC code #{item[:atc_code]} for #{gtin} longer in swissindex  #{@data_swissindex[gtin][:atc_code]}"
        elsif item[:atc_code].length > @data_swissindex[gtin][:atc_code].length
          shorter_in_swissmedic << "ATC code #{atc_code} for #{gtin} shorter in swissindex  #{@data_swissindex[gtin][:atc_code]}"
        else
          different_atc << "ATC code #{atc_code} for #{gtin} differs from swissindex  #{@data_swissindex[gtin][:atc_code]}"
        end
        unless @data_bag[gtin]
          not_in_bag << "#{gtin}: Not in bag #{item}"
          next
        end
      }
      Util.info  "Result of verifing data from swissmedic:
  swissmedic had #{@data_swissmedic.size} entries. Fetched from #{@swissmedic.origin}
  swissindex #{@data_swissindex.size} entries. Fetched from #{@swissindex.origin}
  bag #{@data_bag.size} entries. #{@bag_entries_without_gtin.size} entries had no GTIN field. Fetched from #{@bag.origin}
  Matching #{matching.size} items.
  Not in bag #{not_in_bag.size}
  Not in swissindex #{not_in_swissindex.size}
  Comparing ATC-Codes between swissmedic and swissindex
"
   topic = 'compare swissmedic to swisssindex'
   report(topic, 'atc match in swissindex and swissmedic', matching_atc_codes)
   report(topic, 'atc are different in swissindex and swissmedic', different_atc)
   report(topic, 'atc are the same in swissindex and swissmedic', matching_atc_codes)
   report(topic, 'atc are shorter in swissindex', shorter_in_swissmedic)
   report(topic, 'atc are longer in swissindex', longer_in_swissindex)
    end

    def compare
      all_gtin = @data_bag.merge(@data_swissindex).merge(@data_swissmedic).sort
      matching_atc_codes = []
      not_in_bag = []
      not_in_swissmedic = []
      not_in_swissindex = []
      different_atc = []
      all_gtin.each{
        |gtin, item|
        if @data_bag[gtin] and @data_swissindex[gtin] and @data_swissmedic[gtin] and
          @data_bag[gtin][:atc_code] == @data_swissindex[gtin][:atc_code] and
          @data_bag[gtin][:atc_code] == @data_swissindex[gtin][:atc_code]
          matching_atc_codes << "#{gtin}: ATC-Code #{@data_bag[gtin][:atc_code]} matches in bag, swissmedic and swissindex"
          next
        end
        unless @data_swissmedic[gtin]
          not_in_swissmedic << "#{gtin}: Not in swissmedic #{item}"
          next
        end
        unless @data_swissindex[gtin]
          not_in_swissindex << "#{gtin}: Not in swissindex #{item}"
          next
        end
        unless @data_bag[gtin]
          not_in_bag << "#{gtin}: Not in bag #{item}"
          next
        end
        different_atc << "#{gtin}: ATC code differs bag #{@data_bag[gtin][:atc_code]} swissindex  #{@data_swissindex[gtin][:atc_code]}"
      }
      Util.info  "Comparing all GTIN-codes:
  Found infos about #{all_gtin.size} entries
  bag #{@data_bag.size} entries. #{@bag_entries_without_gtin.size} entries had no GTIN field. Fetched from #{@bag.origin}
  swissindex #{@data_swissindex.size} entries. Fetched from #{@swissindex.origin}
  swissmedic #{@data_swissmedic.size} entries. Fetched from #{@swissmedic.origin}
"
      topic = 'compare all'
      report(topic, SameInAll,          matching_atc_codes)
      report(topic, AtcNotInBag,        not_in_bag)
      report(topic, AtcNotInSwissindex, not_in_swissindex)
      report(topic, AtcNotInSwissmedic, not_in_swissmedic)
      report(topic, AtcDifferent,       different_atc)
    end
  end
  class Swissmedic
    def Swissmedic.get_latest
      Util.debug_msg 'test'
      @index_url = 'https://www.swissmedic.ch/arzneimittel/00156/00221/00222/00230/index.html?lang=de'
      Util.debug_msg("swissmedicPlugin @index_url #{@index_url}")
      latest_name, target =  Util.get_latest_and_dated_name('Packungen', '.xlsx')
      if File.exist?(target)
        Util.debug_msg "#{__FILE__}: #{__LINE__} skip writing #{target} as it already exists and is #{File.size(target)} bytes."
        return target
      end
      Util.debug_msg "target #{target} #{latest_name}"
      latest = ''
      if(File.exist? latest_name)
        latest = File.read latest_name
        return latest_name
      end

      agent=Mechanize.new
      page = agent.get @index_url
      links = page.links.select do |link|
        /Packungen/iu.match link.attributes['title']
      end
      link = links.first or raise "could not identify url to Packungen.xlsx"
      file = agent.get(link.href)
      download = file.body

      if(download[-1] != ?\n)
        download << "\n"
      end
      if(!File.exist?(latest_name) or download.size != File.size(latest_name))
        File.open(target, 'w') { |fh| fh.puts(download) }
        msg = "#{__FILE__}: #{__LINE__} updated download.size is #{download.size} -> #{target} #{File.size(target)}"
        msg += "#{target} now #{File.size(target)} bytes != #{latest_name} #{File.size(latest_name)}" if File.exists?(latest_name)
        Util.debug_msg(msg)
        target
      else
        Util.debug_msg "#{__FILE__}: #{__LINE__} skip writing #{target} as #{latest_name} is #{File.size(latest_name)} bytes. Returning latest"
        nil
      end
    end

  end
end
