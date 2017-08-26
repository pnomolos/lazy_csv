# frozen_string_literal: true

class SmarterCSV
  class HeaderSizeMismatch < RuntimeError; end

  class IncorrectOption < RuntimeError; end

  DEFAULT_OPTIONS = {
    col_sep: ',',
    row_sep: $INPUT_RECORD_SEPARATOR,
    quote_char: '"',
    force_simple_split: false,
    verbose: false,
    remove_empty_values: true,
    remove_zero_values: false,
    remove_values_matching: nil,
    remove_empty_hashes: true,
    strip_whitespace: true,
    convert_values_to_numeric: true,
    strip_chars_from_headers: nil,
    user_provided_headers: nil,
    headers_in_file: true,
    comment_regexp: /^#/,
    chunk_size: nil,
    key_mapping_hash: nil,
    downcase_header: true,
    strings_as_keys: false,
    file_encoding: 'utf-8',
    remove_unmapped_keys: false,
    keep_original_headers: false,
    value_converters: nil,
    skip_lines: nil,
    force_utf8: false,
    invalid_byte_sequence: ''
  }.freeze

  def initialize(input, options)
    @options = DEFAULT_OPTIONS.merge(options)
    @options[:invalid_byte_sequence] ||= ''
    @csv_options = @options.select { |k, _| %i[col_sep row_sep quote_char].include?(k) }
    @file_line_count = 0
    @csv_line_count = 0
    @io = input.respond_to?(:readline) ? input : File.open(input, "r:#{@options[:file_encoding]}")
    @headers = []
    begin
      initialize_io
    rescue
      @io.close
      raise
    end
  end

  def initialize_io
    headerA = []

    unless @options[:row_sep].is_a?(String) || @options[:row_sep] == :auto
      raise SmarterCSV::IncorrectOption, 'ERROR [smarter_csv]: :row_sep must be a string or :auto'
    end

    if (@options[:force_utf8] || @options[:file_encoding] =~ /utf-8/i) && (@io.respond_to?(:external_encoding) && @io.external_encoding != Encoding.find('UTF-8') || @io.respond_to?(:encoding) && f.encoding != Encoding.find('UTF-8'))
      puts 'WARNING: you are trying to process UTF-8 input, but did not open the input with "b:utf-8" option. See README file "NOTES about File Encodings".'
    end

    if @options[:row_sep] == :auto
      @options[:row_sep] = SmarterCSV.guess_line_ending(@io, @options)
      @io.rewind
    end

    [0, @options[:skip_lines].to_i].max.times { @io.readline(@options[:row_sep]) }

    if @options[:headers_in_file] # extract the header line
      file_headerA = read_header
      file_header_size = file_headerA.size
    elsif @options[:user_provided_headers].nil? && @options[:parse_to_arrays].nil?
      raise SmarterCSV::IncorrectOption, 'ERROR [smarter_csv]: If :headers_in_file is set to false, you have to provide :user_provided_headers or :parse_to_arrays'
    end

    if @options[:user_provided_headers] && @options[:user_provided_headers].class == Array && !@options[:user_provided_headers].empty?
      # use user-provided headers
      headerA = @options[:user_provided_headers]
      #if defined?(file_header_size) && !file_header_size.nil?
        if headerA.size != file_header_size
          raise SmarterCSV::HeaderSizeMismatch, "ERROR [smarter_csv]: :user_provided_headers defines #{headerA.size} headers !=  CSV-file #{input} has #{file_header_size} headers"
        end
      #end
    else
      headerA = file_headerA
    end
    headerA.map! { |x| x.to_sym } unless @options[:strings_as_keys] || @options[:keep_original_headers]

    unless @options[:user_provided_headers] # wouldn't make sense to re-map user provided headers
      key_mappingH = @options[:key_mapping]

      # do some key mapping on the keys in the file header
      #   if you want to completely delete a key, then map it to nil or to ''
      if !key_mappingH.nil? && key_mappingH.class == Hash && !key_mappingH.keys.empty?
        headerA.map! { |x| key_mappingH.key?(x) ? (key_mappingH[x].nil? ? nil : key_mappingH[x]) : (@options[:remove_unmapped_keys] ? nil : x) }
      end
    end

    @headers = headerA
  end

  def self.process(input, options = {}) # first parameter: filename or input object with readline method
    new(input, options).read
  end

  def read
    if @options[:chunk_size].to_i > 0
      use_chunks = true
      chunk_size = @options[:chunk_size].to_i
      chunk_count = 0
      chunk = []
    else
      use_chunks = false
    end

    # seek_pos = @io.pos

    enumerator = Enumerator::Lazy.new(@io.each_line(@options[:row_sep])) do |yielder, line|
      yielder.yield read_line(line, @options, @csv_options)
    end

    enumerator = enumerator.reject(&:nil?) if @options[:remove_empty_hashes]

    enumerator.instance_variable_set(:@io, @io)
    enumerator.instance_variable_set(:@seek_pos, @io.pos)

    class << enumerator
      def rewind
        @io.seek(@seek_pos)
        super
      end
    end

    return enumerator

    c = @io.each_line(@options[:row_sep]).lazy.map do |line|
      read_line(line, @options, @csv_options)
    end.reject(&:nil?)

    c.instance_variable_set(:@io, @io)
    c.instance_variable_set(:@seek_pos, @io.pos)



    return c
    #
    #   next unless hash
    #
    #
    #   if use_chunks
    #     chunk << hash # append temp result to chunk
    #
    #     if chunk.size >= chunk_size || f.eof? # if chunk if full, or EOF reached
    #       # do something with the chunk
    #       if block_given?
    #         next chunk # do something with the hashes in the chunk in the block
    #       else
    #         result << chunk # not sure yet, why anybody would want to do this without a block
    #       end
    #       chunk_count += 1
    #       chunk = [] # initialize for next chunk of data
    #     end
    #
    #     # print new line to retain last processing line message
    #     print "\n" if @options[:verbose]
    #
    #     # last chunk:
    #     if !chunk.nil? && !chunk.empty?
    #       # do something with the chunk
    #       if block_given?
    #         next chunk # do something with the hashes in the chunk in the block
    #       else
    #         result << chunk # not sure yet, why anybody would want to do this without a block
    #       end
    #       chunk_count += 1
    #       chunk = [] # initialize for next chunk of data
    #     end
    #   end
    # end
  rescue
    @io.close
    raise
  end

  private

  def read_header
    # process the header line in the CSV file..
    # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
    header = @io.readline(@options[:row_sep]).sub(@options[:comment_regexp], '').chomp(@options[:row_sep])
    header = header.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: @options[:invalid_byte_sequence]) if @options[:force_utf8] || @options[:file_encoding] !~ /utf-8/i

    @file_line_count += 1
    @csv_line_count += 1
    header = header.gsub(@options[:strip_chars_from_headers], '') if @options[:strip_chars_from_headers]

    if (header =~ /#{@options[:quote_char]}/) && (!@options[:force_simple_split])
      file_headerA = begin
        CSV.parse(header, @csv_options).flatten.collect! { |x| x.nil? ? '' : x } # to deal with nil values from CSV.parse
      rescue CSV::MalformedCSVError
        raise $ERROR_INFO, "#{$ERROR_INFO} [SmarterCSV: csv line #{csv_line_count}]", $ERROR_INFO.backtrace
      end
    else
      file_headerA = header.split(@options[:col_sep])
    end
    file_headerA.map! { |x| x.tr(@options[:quote_char], '') }
    file_headerA.map! { |x| x.strip } if @options[:strip_whitespace]
    unless @options[:keep_original_headers]
      file_headerA.map! { |x| x.gsub(/\s+|-+/, '_') }
      file_headerA.map! { |x| x.downcase } if @options[:downcase_header]
    end

    file_headerA
  end

  # acts as a road-block to limit processing when iterating over all k/v pairs of a CSV-hash:
  def self.only_or_except_limit_execution(options, option_name, key)
    if options[option_name].is_a?(Hash)
      if options[option_name].key?(:except)
        return true if Array(options[option_name][:except]).include?(key)
      elsif options[option_name].key?(:only)
        return true unless Array(options[option_name][:only]).include?(key)
      end
    end
    false
  end

  # limitation: this currently reads the whole file in before making a decision
  def self.guess_line_ending(filehandle, options)
    counts = { "\n" => 0, "\r" => 0, "\r\n" => 0 }
    quoted_char = false

    # count how many of the pre-defined line-endings we find
    # ignoring those contained within quote characters
    last_char = nil
    filehandle.each_char do |c|
      quoted_char = !quoted_char if c == options[:quote_char]
      next if quoted_char

      if last_char == "\r"
        if c == "\n"
          counts["\r\n"] +=  1
        else
          counts["\r"] += 1 # \r are counted after they appeared, we might
        end
      elsif c == "\n"
        counts["\n"] += 1
      end
      last_char = c
    end
    counts["\r"] += 1 if last_char == "\r"
    # find the key/value pair with the largest counter:
    k, = counts.max_by { |_, v| v }
    k # the most frequent one is it
  end

  def read_line(line, options, csv_options)
    # replace invalid byte sequence in UTF-8 with question mark to avoid errors
    line = line.force_encoding('utf-8').encode('utf-8', invalid: :replace, undef: :replace, replace: @options[:invalid_byte_sequence]) if @options[:force_utf8] || @options[:file_encoding] !~ /utf-8/i

    @file_line_count += 1
    @csv_line_count += 1
    print format("processing file line %10d, csv line %10d\r", @file_line_count, @csv_line_count) if @options[:verbose]
    return if line =~ @options[:comment_regexp] # ignore all comment lines if there are any

    # cater for the quoted csv data containing the row separator carriage return character
    # in which case the row data will be split across multiple lines (see the sample content in spec/fixtures/carriage_returns_rn.csv)
    # by detecting the existence of an uneven number of quote characters
    multiline = line.count(@options[:quote_char]) % 2 == 1
    while line.count(@options[:quote_char]) % 2 == 1
      line += @io.readline(@options[:row_sep])
      @file_line_count += 1
    end
    print format("\nline contains uneven number of quote chars so including content through file line %d\n", file_line_count) if @options[:verbose] && multiline

    line.chomp!(@options[:row_sep])

    if (line =~ /#{@options[:quote_char]}/) && (!@options[:force_simple_split])
      dataA = begin
        CSV.parse(line, @csv_options).flatten.collect! { |x| x.nil? ? '' : x } # to deal with nil values from CSV.parse
      rescue CSV::MalformedCSVError
        raise $ERROR_INFO, "#{$ERROR_INFO} [SmarterCSV: csv line #{@csv_line_count}]", $ERROR_INFO.backtrace
      end
    else
      dataA = line.split(@options[:col_sep])
    end
    dataA.map! { |x| x.gsub(%r{@options[:quote_char]}, '') }
    dataA.map! { |x| x.strip } if @options[:strip_whitespace]
    if @options[:parse_to_arrays]
      hash = dataA

      if @options[:remove_empty_values]
        hash.pop while !hash.empty? && (hash.last.nil? || hash.last !~ /[^[:space:]]/)
      end
      if @options[:remove_zero_values]
        hash.pop while !hash.last.nil? && hash.last =~ /^(\d+|\d+\.\d+)$/ && hash.last.to_f == 0
      end

      if @options[:convert_values_to_numeric]
        hash.each_with_index do |v, k|
          # deal with the :only / :except @options to :convert_values_to_numeric
          next if SmarterCSV.only_or_except_limit_execution(@options, :convert_values_to_numeric, k)

          # convert if it's a numeric value:
          case v
          when /^[+-]?\d+\.\d+$/
            hash[k] = v.to_f
          when /^[+-]?\d+$/
            hash[k] = v.to_i
          end
        end

        if @options[:value_converters]
          hash.each_with_index do |v, k|
            converter = @options[:value_converters][k]
            next unless converter
            hash[k] = converter.convert(v)
          end
        end
      end

    else
      # TODO: This is used once, remove the core extension?
      hash = Hash.zip(@headers, dataA) # from Facets of Ruby library
      # make sure we delete any key/value pairs from the hash, which the user wanted to delete:
      # Note: Ruby < 1.9 doesn't allow empty symbol literals!
      hash.delete(nil); hash.delete('')
      eval('hash.delete(:"")') if RUBY_VERSION.to_f > 1.8

      # remove empty values using the same regexp as used by the rails blank? method
      # which caters for double \n and \r\n characters such as "1\r\n\r\n2" whereas the original check (v =~ /^\s*$/) does not
      hash.delete_if { |_k, v| v.nil? || v !~ /[^[:space:]]/ } if @options[:remove_empty_values]

      hash.delete_if { |_k, v| !v.nil? && v =~ /^(\d+|\d+\.\d+)$/ && v.to_f == 0 } if @options[:remove_zero_values] # values are typically Strings!
      hash.delete_if { |_k, v| v =~ @options[:remove_values_matching] } if @options[:remove_values_matching]
      if @options[:convert_values_to_numeric]
        hash.each do |k, v|
          # deal with the :only / :except @options to :convert_values_to_numeric
          next if SmarterCSV.only_or_except_limit_execution(@options, :convert_values_to_numeric, k)

          # convert if it's a numeric value:
          case v
          when /^[+-]?\d+\.\d+$/
            hash[k] = v.to_f
          when /^[+-]?\d+$/
            hash[k] = v.to_i
          end
        end
      end

      if @options[:value_converters]
        hash.each do |k, v|
          converter = @options[:value_converters][k]
          next unless converter
          hash[k] = converter.convert(v)
        end
      end
    end

    return if @options[:remove_empty_hashes] && hash.empty?

    if hash.is_a?(Array)
      hash.each(&:freeze)
    else
      hash.each { |_, v| v.freeze }
    end
  end
end
