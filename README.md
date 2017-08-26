# LazyCSV

[![Build Status](https://secure.travis-ci.org/pnomolos/lazy_csv.svg?branch=master)](http://travis-ci.org/pnomolos/lazy_csv) [![Gem Version](https://badge.fury.io/rb/lazy_csv.svg)](http://badge.fury.io/rb/lazy_csv)

`lazy_csv` is a Ruby Gem for lazy importing of CSV Files as Arrays or Hashes,
suitable for direct processing with Mongoid or ActiveRecord
and parallel processing with Resque or Sidekiq.  

It was originally a fork of [Smarter CSV](https://github.com/tilo/smarter_csv) but has since
diverged significantly.

`lazy_csv` has lots of features:
 * returns an Enumerator::Lazy so you lazily-load the file without being constrained to a single block for processing
 * able to process large CSV-files
 * return a Hash for each line of the CSV file, so we can quickly use the results for either creating MongoDB or ActiveRecord entries, or further processing with Resque
 * able to pass a block to the `process` method, so data from the CSV file can be directly processed (e.g. Resque.enqueue )
 * allows to have a bit more flexible input format, where comments are possible, and col_sep,row_sep can be set to any character sequence, including control characters.
 * able to re-map CSV "column names" to Hash-keys of your choice (normalization)
 * able to ignore "columns" in the input (delete columns)
 * able to eliminate nil or empty fields from the result hashes (default)

NOTE; This Gem is only for importing CSV files - writing of CSV files is not supported at this time.

## Notes/Warnings

At this time if you pass a filename to `process` it won't be closed at the end.  For the time being
it's probably best to use an instance of `IO` that can be closed when you're done.

### Why?

Smarter CSV met a lot of my needs but I wanted to be able to pass a lazy enumerator through my code
as opposed to running everything through a single block - I want the control of when reads are made
for each line, as opposed to dumbly iterating over the whole thing.  This allowed for better control
in some cases where the CSV was divided into sections and each section could be handled independently.

SmarterCSV also offered chunked processing (so you could process x rows at once).  I'm hoping to have
that return at some point but it's not high on the priority list right now.

#### Originally from Smarter CSV - Why?

Ruby's CSV library's API is pretty old, and it's processing of CSV-files returning Arrays of Arrays feels 'very close to the metal'. The output is not easy to use - especially not if you want to create database records from it. Another shortcoming is that Ruby's CSV library does not have good support for huge CSV-files, e.g. there is no support for 'chunking' and/or parallel processing of the CSV-content (e.g. with Resque or Sidekiq),

As the existing CSV libraries didn't fit my needs, I was writing my own CSV processing - specifically for use in connection with Rails ORMs like Mongoid, MongoMapper or ActiveRecord. In those ORMs you can easily pass a hash with attribute/value pairs to the create() method. The lower-level Mongo driver and Moped also accept larger arrays of such hashes to create a larger amount of records quickly with just one call.

### Examples

The two main choices you have in terms of how to call `LazyCSV.process` are:
 * calling `process` with or without a block

Tip: If you are uncertain about what line endings a CSV-file uses, try specifying `row_sep: :auto` as part of the options.
But this could be slow, because it will try to analyze each CSV file first. If you want to speed things up, set the `:row_sep` manually! Checkout Example 5 for unusual `:row_sep` and `:col_sep`.

#### Example 1a: How LazyCSV processes CSV-files as array of hashes:
Please note how each hash contains only the keys for columns with non-null values.

     $ cat pets.csv
     first name,last name,dogs,cats,birds,fish
     Dan,McAllister,2,,,
     Lucy,Laweless,,5,,
     Miles,O'Brian,,,,21
     Nancy,Homes,2,,1,
     $ irb
     > require 'lazy_csv'
      => true
     > pets_by_owner = LazyCSV.process('/tmp/pets.csv').to_a
      => [ {:first_name=>"Dan", :last_name=>"McAllister", :dogs=>"2"},
           {:first_name=>"Lucy", :last_name=>"Laweless", :cats=>"5"},
           {:first_name=>"Miles", :last_name=>"O'Brian", :fish=>"21"},
           {:first_name=>"Nancy", :last_name=>"Homes", :dogs=>"2", :birds=>"1"}
         ]


#### Example 1b: How LazyCSV processes CSV-files as chunks, returning arrays of hashes:
Please note how the returned array contains two sub-arrays containing the chunks which were read, each chunk containing 2 hashes.
In case the number of rows is not cleanly divisible by `:chunk_size`, the last chunk contains fewer hashes.

     > pets_by_owner = LazyCSV.process('/tmp/pets.csv', {:chunk_size => 2, :key_mapping => {:first_name => :first, :last_name => :last}}).to_a
       => [ [ {:first=>"Dan", :last=>"McAllister", :dogs=>"2"}, {:first=>"Lucy", :last=>"Laweless", :cats=>"5"} ],
            [ {:first=>"Miles", :last=>"O'Brian", :fish=>"21"}, {:first=>"Nancy", :last=>"Homes", :dogs=>"2", :birds=>"1"} ]
          ]

#### Example 2: Reading a CSV-File in one Chunk, returning one Array of Hashes:

    filename = '/tmp/input_file.txt' # TAB delimited file, each row ending with Control-M
    recordsA = LazyCSV.process(filename, {:col_sep => "\t", :row_sep => "\cM"}).to_a  # no block given

    => returns an array of hashes

#### Example 3: Populate a MySQL or MongoDB Database with LazyCSV:

    # without using chunks:
    filename = '/tmp/some.csv'
    options = {:key_mapping => {:unwanted_row => nil, :old_row_name => :new_name}}
    n = LazyCSV.process(filename, options) do |array|
          # we're passing a block in, to process each resulting hash / =row (the block takes array of hashes)
          # when chunking is not enabled, there is only one hash in each array
          MyModel.create( array.first )
    end

     => returns number of chunks / rows we processed

#### Example 6: Using Value Converters

NOTE: If you use `key_mappings` and `value_converters`, make sure that the value converters has references the keys based on the final mapped name, not the original name in the CSV file.

    $ cat spec/fixtures/with_dates.csv
    first,last,date,price
    Ben,Miller,10/30/1998,$44.50
    Tom,Turner,2/1/2011,$15.99
    Ken,Smith,01/09/2013,$199.99
    $ irb
    > require 'lazy_csv'
    > require 'date'

    # define a custom converter class, which implements self.convert(value)
    class DateConverter
      def self.convert(value)
        Date.strptime( value, '%m/%d/%Y') # parses custom date format into Date instance
      end
    end

    class DollarConverter
      def self.convert(value)
        value.sub('$','').to_f
      end
    end

    options = {:value_converters => {:date => DateConverter, :price => DollarConverter}}
    data = LazyCSV.process("spec/fixtures/with_dates.csv", options)
    data[0][:date]
      => #<Date: 1998-10-30 ((2451117j,0s,0n),+0s,2299161j)>
    data[0][:date].class
      => Date
    data[0][:price]
      => 44.50
    data[0][:price].class
      => Float

## Parallel Processing
[Jack](https://github.com/xjlin0) wrote an interesting article about [Speeding up CSV parsing with parallel processing](http://xjlin0.github.io/tech/2015/05/25/faster-parsing-csv-with-parallel-processing)

## Documentation

The `process` method reads and processes a "generalized" CSV file and returns an `Enumerator::Lazy`.
This can either be iterated over (via `each`) or converted into a record set by calling `to_a`.

    LazyCSV.process(filename_or_io, options={}, &block)

The options and the block are optional.

`LazyCSV.process` supports the following options:

     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :col_sep                    |   ','    | column separator                                                                     |
     | :row_sep                    | $/ ,"\n" | row separator or record separator , defaults to system's $/ , which defaults to "\n" |
     |                             |          | This can also be set to :auto, but will process the whole cvs file first  (slow!)    |
     | :quote_char                 |   '"'    | quotation character                                                                  |
     | :comment_regexp             |   /^#/   | regular expression which matches comment lines (see NOTE about the CSV header)       |
     | :parse_to_arrays            |   false  | if set, returns a zero-indexed array as opposed to a hash keyed by headers           |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :key_mapping                |   nil    | a hash which maps headers from the CSV file to keys in the result hash               |
     | :remove_unmapped_keys       |   false  | when using :key_mapping option, should non-mapped keys / columns be removed?         |
     | :downcase_header            |   true   | downcase all column headers                                                          |
     | :strings_as_keys            |   false  | use strings instead of symbols as the keys in the result hashes                      |
     | :strip_whitespace           |   true   | remove whitespace before/after values and headers                                    |
     | :keep_original_headers      |   false  | keep the original headers from the CSV-file as-is.                                   |
     |                             |          | Disables other flags manipulating the header fields.                                 |
     | :user_provided_headers      |   nil    | *careful with that axe!*                                                             |
     |                             |          | user provided Array of header strings or symbols, to define                          |
     |                             |          | what headers should be used, overriding any in-file headers.                         |
     |                             |          | You can not combine the :user_provided_headers and :key_mapping options              |
     | :strip_chars_from_headers   |   nil    | RegExp to remove extraneous characters from the header line (e.g. if headers are quoted) |
     | :headers_in_file            |   true   | Whether or not the file contains headers as the first line.                          |
     |                             |          | Important if the file does not contain headers,                                      |
     |                             |          | otherwise you would lose the first line of data.                                     |
     | :skip_lines                 |   nil    | how many lines to skip before the first line or header line is processed             |
     | :force_utf8                 |   false  | force UTF-8 encoding of all lines (including headers) in the CSV file                |
     | :invalid_byte_sequence      |   ''     | how to replace invalid byte sequences with                                           |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :value_converters           |   nil    | supply a hash of :header => KlassName; the class needs to implement self.convert(val)|
     | :remove_empty_values        |   true   | remove values which have nil or empty strings as values                              |
     | :remove_zero_values         |   true   | remove values which have a numeric value equal to zero / 0                           |
     | :remove_values_matching     |   nil    | removes key/value pairs if value matches given regular expressions. e.g.:            |
     |                             |          | /^\$0\.0+$/ to match $0.00 , or /^#VALUE!$/ to match errors in Excel spreadsheets    |
     | :convert_values_to_numeric  |   true   | converts strings containing Integers or Floats to the appropriate class              |
     |                             |          |      also accepts either {:except => [:key1,:key2]} or {:only => :key3}              |
     | :remove_empty_hashes        |   true   | remove / ignore any hashes which don't have any key/value pairs                      |
     | :file_encoding              |   utf-8  | Set the file encoding eg.: 'windows-1252' or 'iso-8859-1'                            |
     | :force_simple_split         |   false  | force simiple splitting on :col_sep character for non-standard CSV-files.            |
     |                             |          | e.g. when :quote_char is not properly escaped                                        |
     | :verbose                    |   false  | print out line number while processing (to track down problems in input files)       |


#### NOTES about File Encodings:
 * if you have a CSV file which contains unicode characters, you can process it as follows:


       File.open(filename, "r:bom|utf-8") do |f|
         data = LazyCSV.process(f);
       end

* if the CSV file with unicode characters is in a remote location, similarly you need to give the encoding as an option to the `open` call:

       require 'open-uri'
       file_location = 'http://your.remote.org/sample.csv'
       open(file_location, 'r:utf-8') do |f|   # don't forget to specify the UTF-8 encoding!!
         data = LazyCSV.process(f)
       end

#### NOTES about CSV Headers:
 * as this method parses CSV files, it is assumed that the first line of any file will contain a valid header
 * the first line with the CSV header may or may not be commented out according to the :comment_regexp
 * any occurences of :comment_regexp or :row_sep will be stripped from the first line with the CSV header
 * any of the keys in the header line will be downcased, spaces replaced by underscore, and converted to Ruby symbols before being used as keys in the returned Hashes
 * you can not combine the :user_provided_headers and :key_mapping options
 * if the incorrect number of headers are provided via :user_provided_headers, exception LazyCSV::HeaderSizeMismatch is raised

#### NOTES on Key Mapping:
 * keys in the header line of the file can be re-mapped to a chosen set of symbols, so the resulting Hashes can be better used internally in your application (e.g. when directly creating MongoDB entries with them)
 * if you want to completely delete a key, then map it to nil or to '', they will be automatically deleted from any result Hash
 * if you have input files with a large number of columns, and you want to ignore all columns which are not specifically mapped with :key_mapping, then use option :remove_unmapped_keys => true

#### NOTES on improper quotation and unwanted characters in headers:
 * some CSV files use un-escaped quotation characters inside fields. This can cause the import to break. To get around this, use the `:force_simple_split => true` option in combination with `:strip_chars_from_headers => /[\-"]/` . This will also significantly speed up the import.
   If you would force a different :quote_char instead (setting it to a non-used character), then the import would be up to 5-times slower than using `:force_simple_split`.

## See also:

  http://www.unixgods.org/~tilo/Ruby/process_csv_as_hashes.html



## Installation

Add this line to your application's Gemfile:

    gem 'lazy_csv'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install lazy_csv

## Upcoming

Planned in the next releases:
 * programmatic header transformations

## Changes

#### 0.5.0 (2017-08-26)
 * Forked to lazy_csv and versioning reset as it's not ready for primetime yet :)

## SmarterCSV Changes

#### 1.1.4 (2017-01-16)
 * fixing UTF-8 related bug which was introduced in 1.1.2 (thank to Tirdad C.)

#### 1.1.3 (2016-12-30)
 * added warning when options indicate UTF-8 processing, but input filehandle is not opened with r:UTF-8 option

#### 1.1.2 (2016-12-29)
 * added option `invalid_byte_sequence` (thanks to polycarpou)
 * added comments on handling of UTF-8 encoding when opening from File vs. OpenURI (thanks to KevinColemanInc)

#### 1.1.1 (2016-11-26)
 * added option to `skip_lines` (thanks to wal)
 * added option to `force_utf8` encoding (thanks to jordangraft)
 * bugfix if no headers in input data (thanks to esBeee)
 * ensure input file is closed (thanks to waldyr)
 * improved verbose output (thankd to benmaher)
 * improved documentation

#### 1.1.0 (2015-07-26)
 * added feature :value_converters, which allows parsing of dates, money, and other things (thanks to Raphaël Bleuse, Lucas Camargo de Almeida, Alejandro)
 * added error if :headers_in_file is set to false, and no :user_provided_headers are given (thanks to innhyu)
 * added support to convert dashes to underscore characters in headers (thanks to César Camacho)
 * fixing automatic detection of \r\n line-endings (thanks to feens)

#### 1.0.19 (2014-10-29)
 * added option :keep_original_headers to keep CSV-headers as-is (thanks to Benjamin Thouret)

#### 1.0.18 (2014-10-27)
 * added support for multi-line fields / csv fields containing CR (thanks to Chris Hilton) (issue #31)

#### 1.0.17 (2014-01-13)
 * added option to set :row_sep to :auto , for automatic detection of the row-separator (issue #22)

#### 1.0.16 (2014-01-13)
 * :convert_values_to_numeric option can now be qualified with :except or :only (thanks to Hugo Lepetit)
 * removed deprecated `process_csv` method

#### 1.0.15 (2013-12-07)
 * new option:
   * :remove_unmapped_keys  to completely ignore columns which were not mapped with :key_mapping (thanks to Dave Sanders)

#### 1.0.14 (2013-11-01)
 * added GPL-2 and MIT license to GEM spec file; if you need another license contact me

#### 1.0.13 (2013-11-01)    ### YANKED!
 * added GPL-2 license to GEM spec file; if you need another license contact me

#### 1.0.12 (2013-10-15)
 * added RSpec tests

#### 1.0.11 (2013-09-28)
 * bugfix : fixed issue #18 - fixing issue with last chunk not being properly returned (thanks to Jordan Running)
 * added RSpec tests

#### 1.0.10 (2013-06-26)
 * bugfix : fixed issue #14 - passing options along to CSV.parse (thanks to Marcos Zimmermann)

#### 1.0.9 (2013-06-19)
 * bugfix : fixed issue #13 with negative integers and floats not being correctly converted (thanks to Graham Wetzler)

#### 1.0.8 (2013-06-01)

 * bugfix : fixed issue with nil values in inputs with quote-char (thanks to Félix Bellanger)
 * new options:
    * :force_simple_split : to force simiple splitting on :col_sep character for non-standard CSV-files. e.g. without properly escaped :quote_char
    * :verbose : print out line number while processing (to track down problems in input files)

#### 1.0.7 (2013-05-20)

 * allowing process to work with objects with a 'readline' method (thanks to taq)
 * added options:
    * :file_encoding : defaults to utf8  (thanks to MrTin, Paxa)

#### 1.0.6 (2013-05-19)

 * bugfix : quoted fields are now correctly parsed

#### 1.0.5 (2013-05-08)

 * bugfix : for :headers_in_file option

#### 1.0.4 (2012-08-17)

 * renamed the following options:
    * :strip_whitepace_from_values => :strip_whitespace   - removes leading/trailing whitespace from headers and values

#### 1.0.3 (2012-08-16)

 * added the following options:
    * :strip_whitepace_from_values   - removes leading/trailing whitespace from values

#### 1.0.2 (2012-08-02)

 * added more options for dealing with headers:
    * :user_provided_headers ,user provided Array with header strings or symbols, to precisely define what the headers should be, overriding any in-file headers (default: nil)
    * :headers_in_file , if the file contains headers as the first line (default: true)

#### 1.0.1 (2012-07-30)

 * added the following options:
    * :downcase_header
    * :strings_as_keys
    * :remove_zero_values
    * :remove_values_matching
    * :remove_empty_hashes
    * :convert_values_to_numeric

 * renamed the following options:
    * :remove_empty_fields => :remove_empty_values


#### 1.0.0 (2012-07-29)

 * renamed `LazyCSV.process_csv` to `LazyCSV.process`.

#### 1.0.0.pre1 (2012-07-29)


## Reporting Bugs / Feature Requests

Please [open an Issue on GitHub](https://github.com/tilo/lazy_csv/issues) if you have feedback, new feature requests, or want to report a bug. Thank you!


## Special Thanks

Many thanks to people who have filed issues and sent comments.
And a special thanks to those who contributed pull requests:

 * [Tilo](https://github.com/tilo)
 * [Jack 0](https://github.com/xjlin0)
 * [Alejandro](https://github.com/agaviria)
 * [Lucas Camargo de Almeida](https://github.com/lcalmeida)
 * [Raphaël Bleuse](https://github.com/bleuse)
 * [feens](https://github.com/feens)
 * [César Camacho](https://github.com/chanko)
 * [innhyu](https://github.com/innhyu)
 * [Benjamin Thouret](https://github.com/benichu)
 * [Chris Hilton](https://github.com/chrismhilton)
 * [Sean Duckett](http://github.com/sduckett)
 * [Alex Ong](http://github.com/khaong)
 * [Martin Nilsson](http://github.com/MrTin)
 * [Eustáquio Rangel](http://github.com/taq)
 * [Pavel](http://github.com/paxa)
 * [Félix Bellanger](https://github.com/Keeguon)
 * [Graham Wetzler](https://github.com/grahamwetzler)
 * [Marcos G. Zimmermann](https://github.com/marcosgz)
 * [Jordan Running](https://github.com/jrunning)
 * [Dave Sanders](https://github.com/DaveSanders)
 * [Hugo Lepetit](https://github.com/giglemad)
 * [esBeee](https://github.com/esBeee)
 * [Waldyr de Souza](https://github.com/waldyr)
 * [Ben Maher](https://github.com/benmaher)
 * [Wal McConnell](https://github.com/wal)
 * [Jordan Graft](https://github.com/jordangraft)
 * [Michael](https://github.com/polycarpou)
 * [Kevin Coleman](https://github.com/KevinColemanInc)
 * [Tirdad C.](https://github.com/tridadc)


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
