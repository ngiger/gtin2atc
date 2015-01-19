# This file was generated by the `rspec --init` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# Require this file using `require "spec_helper"` to ensure that it is only
# loaded once.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
#
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.dirname(__FILE__)

require 'bundler/setup'
Bundler.require

require 'rspec'
require 'webmock/rspec'
require "gtin2atc/builder"


module Gtin2atc
  # we override here a few directories to make input/output when running specs to
  # be in different places compared when running
  SpecData       = File.join(File.dirname(__FILE__), 'data')
  WorkDir        = File.join(File.dirname(__FILE__), 'run')
end

require 'gtin2atc'

module ServerMockHelper
  def cleanup_directories_before_run
    dirs = [  Gtin2atc::WorkDir]
    dirs.each{ |dir| FileUtils.rm_rf(Dir.glob(File.join(dir, '*')), :verbose => false) }
    dirs.each{ |dir| FileUtils.makedirs(dir, :verbose => false) }
  end
  
  def setup_server_mocks
    puts "Running setup_bag_xml_server_mock"
    stub_request(:get, "https://index.ws.e-mediat.net/Swissindex/Pharma/ws_Pharma_V101.asmx?WSDL").
         with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
         to_return(:status => 200, :body => "", :headers => {})
    setup_bag_xml_server_mock
    puts 88
    return
    # setup_bag_xml_server_mock
    # setup_swiss_index_server_mock
    return
    setup_swissmedic_info_server_mock
    setup_epha_server_mock
    setup_bm_update_server_mock
    setup_lppv_server_mock
    setup_migel_server_mock
    setup_medregbm_server_mock
    setup_zurrose_server_mock
  end
  def setup_bag_xml_server_mock
    # zip
    stub_zip_url = 'http://bag.e-mediat.net/SL2007.Web.External/File.axd?file=XMLPublications.zip'
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'XMLPublications.zip'))
    stub_request(:get, stub_zip_url).
      with(:headers => {
        'Accept'          => '*/*',
        'Accept-Encoding' => 'gzip,deflate,identity',
        'Host'            => 'bag.e-mediat.net',
      }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'application/zip; charset=utf-8'},
        :body    => stub_response)
  end
  def setup_swiss_index_server_mock(types =['NonPharma', 'Pharma'], languages=['DE', 'FR'])
    types.each do |type|
      languages.each do |language|
        # wsdl
        stub_wsdl_url = "https://index.ws.e-mediat.net/Swissindex/#{type}/ws_#{type}_V101.asmx?WSDL"
        first_file = File.join(Gtin2atc::SpecData, "wsdl_#{type.downcase}.xml")
        stub_response_wsdl = File.read(File.join(Gtin2atc::SpecData, "wsdl_#{type.downcase}.xml"))
        stub_request(:get, stub_wsdl_url).
          with(:headers => {
            'Accept' => '*/*',
          }).
          to_return(
            :status  => 200,
            :headers => {'Content-Type' => 'text/xml; charset=utf-8'},
            :body    => stub_response_wsdl)
        # soap (dummy)
        stub_soap_url = 'https://example.com/test'
        stub_file = File.join(Gtin2atc::SpecData, "swissindex_#{type}_#{language}.xml")
        stub_response = File.read(stub_file)
        stub_request(:post, "https://example.com/test").
          with(:body => "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<soap:Envelope xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\">\n<soap:Body>\n  <lang xmlns=\"http://swissindex.e-mediat.net/Swissindex#{type}_out_V101\">#{language}</lang>\n</soap:Body>\n</soap:Envelope>\n",
                :headers => {'Accept'=>'*/*', 'Content-Type'=>'text/xml;charset=UTF-8', 'Soapaction'=>'"http://example.com/DownloadAll"', 'User-Agent'=>'Ruby'}).
          to_return(:status => 200, :body => stub_response, :headers => {})
      end
    end
  end

  def setup_swissmedic_server_mock
    stub_request(:get, "https://www.swissmedic.ch/arzneimittel/00156/00221/00222/00230/index.html?lang=de").
      with(:headers => {'Accept'=>'*/*', 'Accept-Charset'=>'ISO-8859-1,utf-8;q=0.7,*;q=0.7', 'Accept-Encoding'=>'gzip,deflate,identity', 'Accept-Language'=>'en-us,en;q=0.5', 'Connection'=>'keep-alive', 'Host'=>'www.swissmedic.ch', 'Keep-Alive'=>'300', 'User-Agent'=>'Mechanize/2.5.1 Ruby/1.9.3p547 (http://github.com/tenderlove/mechanize/)'}).
      to_return(:status => 200, :body => "", :headers => {})
    puts "Dummy mock"
  return
    puts 9999
    host = 'www.swissmedic.ch'
    {    
#      :orphans  => {:html => '/arzneimittel/00156/00221/00222/00223/00224/00227/00228/index.html?lang=de',       :xls => '/download'},
#      :fridges  => {:html => '/arzneimittel/00156/00221/00222/00235/index.html?lang=de', :xls => '/download'},
      :packages => {:html => '/arzneimittel/00156/00221/00222/00230/index.html?lang=de', :xls => '/download'},
    }.each_pair do |type, urls|
      # html (dummy)
      stub_html_url = "http://#{host}" + urls[:html]
      filename = File.join(Gtin2atc::SpecData, "swissmedic_#{type.to_s}.html")
      
      stub_response = File.read(filename)
      puts "stub_response #{stub_response.size} bytes from #{filename}"
      stub_request(:get, stub_html_url).
        with(:headers => {
          'Accept' => '*/*',
          'Accept-Encoding'=>'gzip,deflate,identity',
          'Host'            => host,
        }).
        to_return(
          :status  => 200,
          :headers => {'Content-Type' => 'text/html; charset=utf-8'},
          :body    => stub_response)
      # xls
      if type == :orphans
        stub_xls_url  = "http://#{host}" + urls[:xls] + "/swissmedic_orphan.xlsx"
        stub_response = File.read(File.join(Gtin2atc::SpecData, "swissmedic_orphan.xlsx"))
      else
        stub_xls_url  = "http://#{host}" + urls[:xls] + "/swissmedic_#{type.to_s}.xlsx"
        stub_response = 'no_such_file'
      end
      puts "stub_response #{stub_response.size} xx"
      stub_request(:get, stub_xls_url).
        with(:headers => {
          'Accept'          => '*/*',
          'Accept-Encoding' => 'gzip,deflate,identity',
          'Host'            => host,
        }).to_return(
          :status  => 200,
          :headers => {'Content-Type' => 'application/octet-stream; charset=utf-8'},
          :body    => stub_response)
    end
  end
  def setup_swissmedic_info_server_mock
    # html (dummy)
    stub_html_url = "http://download.swissmedicinfo.ch/Accept.aspx?ReturnUrl=%2f"
    stub_response = File.read(File.join(Gtin2atc::SpecData, "swissmedic_info.html"))
    stub_request(:get, stub_html_url).
      with(
        :headers => {
          'Accept' => '*/*',
          'Host'   => 'download.swissmedicinfo.ch',
        }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'text/html; charset=utf-8'},
        :body    => stub_response)
    # html (dummy 2)
    stub_html_url = 'http://download.swissmedicinfo.ch/Accept.aspx?ctl00$MainContent$btnOK=1'
    stub_response = File.read(File.join(Gtin2atc::SpecData, "swissmedic_info_2.html"))
    stub_request(:get, stub_html_url).
      with(
        :headers => {
          'Accept' => '*/*',
          'Host'   => 'download.swissmedicinfo.ch',
        }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'text/html; charset=utf-8'},
        :body    => stub_response)
    # zip
    stub_zip_url = 'http://download.swissmedicinfo.ch/Accept.aspx?ctl00$MainContent$BtnYes=1'
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'swissmedic_info.zip'))
    stub_request(:get, stub_zip_url).
      with(
        :headers => {
          'Accept'          => '*/*',
          'Accept-Encoding' => 'gzip,deflate,identity',
          'Host'            => 'download.swissmedicinfo.ch',
        }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'application/zip; charset=utf-8'},
        :body    => stub_response)
  end
  def setup_epha_server_mock
    # csv
    stub_csv_url = 'https://download.epha.ch/cleaned/matrix.csv'
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'epha_interactions.csv'))
    stub_request(:get, stub_csv_url).
      with(:headers => {
        'Accept' => '*/*',
        'Host'   => 'download.epha.ch',
      }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'text/csv; charset=utf-8'},
        :body    => stub_response)
  end
  def setup_bm_update_server_mock
    # txt
    stub_txt_url = 'https://raw.github.com/zdavatz/gtin2atc_files/master/BM_Update.txt'
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'gtin2atc_files_bm_update.txt'))
    stub_request(:get, stub_txt_url).
      with(:headers => {
        'Accept' => '*/*',
        'Host'   => 'raw.github.com',
      }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'text/plain; charset=utf-8'},
        :body    => stub_response)
  end
  def setup_lppv_server_mock
    # txt
    stub_txt_url = 'https://raw.github.com/zdavatz/gtin2atc_files/master/LPPV.txt'
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'gtin2atc_files_lppv.txt'))
    stub_request(:get, stub_txt_url).
      with(:headers => {
        'Accept' => '*/*',
        'Host'   => 'raw.github.com',
      }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'text/plain; charset=utf-8'},
        :body    => stub_response)
  end
  def setup_migel_server_mock
    # xls
    stub_xls_url = 'https://github.com/zdavatz/gtin2atc_files/raw/master/NON-Pharma.xls'
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'gtin2atc_files_nonpharma.xls'))
    stub_request(:get, stub_xls_url).
      with(:headers => {
        'Accept' => '*/*',
        'Host'   => 'github.com',
      }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'application/octet-stream; charset=utf-8'},
        :body    => stub_response)
  end
  def setup_medregbm_server_mock
    # txt betrieb
    stub_txt_url = 'https://www.medregbm.admin.ch/Publikation/CreateExcelListBetriebs'
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'medregbm_betrieb.txt'))
    stub_request(:get, stub_txt_url).
      with(:headers => {
        'Accept' => '*/*',
        'Host'   => 'www.medregbm.admin.ch',
      }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'text/plain; charset=utf-8'},
        :body    => stub_response)
    stub_txt_url = 'https://www.medregbm.admin.ch/Publikation/CreateExcelListMedizinalPersons'
    # txt person
    stub_response = File.read(File.join(Gtin2atc::SpecData, 'medregbm_person.txt'))
    stub_request(:get, stub_txt_url).
      with(:headers => {
        'Accept' => '*/*',
        'Host'   => 'www.medregbm.admin.ch',
      }).
      to_return(
        :status  => 200,
        :headers => {'Content-Type' => 'text/plain; charset=utf-8'},
        :body    => stub_response)
  end
end

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.filter_run :focus
  config.filter_run_excluding :slow
  #config.exclusion_filter = {:slow => true}

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'

  # Helper
  config.include(ServerMockHelper)
end