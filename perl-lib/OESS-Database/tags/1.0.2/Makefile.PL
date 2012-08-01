  use inc::Module::Install;
  
  # Define metadata
 name           'OESS-Database';
 all_from       'lib/OESS/Database.pm';
 license	'apache';
 author		'syseng@grnoc.iu.edu';
  #      
 requires       DBI;
 requires	XML::Simple; 
#requires	DBD::MySQL;
 requires       File::ShareDir; 
 requires	Net::DBus;
  #         # Specific dependencies
  #           requires       'File::Spec'  => '0.80';
  #             test_requires  'Test::More'  => '0.42';
  #               recommends     'Text::CSV_XS'=> '0.50';
  #                 no_index       'directory'   => 'demos';
  #                   install_script 'myscript';
  #                     
 
install_share; 
                        WriteAll;
