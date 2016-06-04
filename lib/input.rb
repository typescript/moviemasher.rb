
module MovieMasher
  # An element in Job#inputs representing media to be included in the mashup,
  # which is eventually rendered into each Output format and uploaded. Inputs
  # are generally combined together in the order they appear, though audio can
  # be mixed by specifying #start times.
  #
  # There are four types of inputs: Type::AUDIO, Type::IMAGE and Type::VIDEO
  # (the three raw types) plus Type::MASH, which allows a Mash to be included
  # like normal audio/video. Mashes can be generated in a web browser utilizing
  # {moviemasher.js}[https://github.com/moviemasher/moviemasher.js] or
  # {angular-moviemasher}[https://github.com/moviemasher/angular-moviemasher]
  # and can include raw elements composited on multiple tracks along with
  # titling, effects and transformations over time.
  #
  # Relevant keys depend on #type, though all inputs have #av, #source and
  # #length keys. After downloading, relevant inputs are probed and will have
  # their #duration set if it's not already. The #no_audio or #no_video keys
  # might change to, as well as #av which relies on them (for instance, from
  # AV::BOTH to AV::VIDEO_ONLY for a video that is found to contain no audio
  # track).
  #
  #   Input.create(
  #     type: Type::VIDEO,
  #     source: 'video.mp4',
  #     fill: 'crop',        # remove pixels outside output's aspect ratio
  #     gain: 0.8,           # reduce volume by 20%
  #     offset: 10,          # remove first ten seconds
  #     length: 50,          # remove everything after the first minute
  #   )
  #
  class Input < Asset
    def self.audio_graphs(inputs)
      graphs = []
      inputs.each do |input|
        next if input[:no_audio]
        case input[:type]
        when Type::VIDEO, Type::AUDIO
          data = {}
          data[:type] = input[:type]
          data[:offset] = input[:offset]
          data[:length] = input[:length]
          data[:start] = input[:start]
          data[:cached_file] = input[:cached_file]
          data[:duration] = input[:duration]
          data[:gain] = input[:gain]
          data[:loop] = input[:loop]
          graphs << data
        when Type::MASH
          quantize = input[:mash][:quantize]
          audio_clips = Mash.clips_having_audio(input[:mash])
          audio_clips.each do |clip|
            media = Mash.media(input[:mash], clip[:id])
            unless media
              raise(Error::JobInput, "couldn't find media #{clip[:id]}")
            end
            next if clip[:no_audio] ||= media[:no_audio]
            raise('could not find cached file') unless media[:cached_file]
            data = {}
            data[:type] = clip[:type]
            data[:offset] = clip[:offset]
            data[:length] = clip[:length]
            data[:start] = input[:start].to_f
            data[:start] += clip[:frame].to_f / quantize.to_f
            data[:cached_file] = media[:cached_file]
            data[:gain] = clip[:gain]
            data[:duration] = media[:duration]
            data[:loop] = clip[:loop]
            graphs << data
          end
        end
      end
      graphs
    end
    # Returns a new instance.
    def self.create(hash = nil)
      (hash.is_a?(Input) ? hash : Input.new(hash))
    end
    def self.init_hash(input)
      _init_time(input, :offset)
      Hashable._init_key(input, :start, FloatUtil::NEG_ONE)
      Hashable._init_key(input, :duration, FloatUtil::ZERO)
      Hashable._init_key(input, :length, 1.0) if Type::IMAGE == input[:type]
      _init_time(input, :length) # ^ image will be one by default, others zero
      input[:base_source] = Transfer.create_if(input[:base_source])
      input[:module_source] = Transfer.create_if(input[:module_source])
      Mash.init_input(input)
      input
    end
    def self.video_graphs(inputs, job)
      graphs = []
      inputs.each do |input|
        next if input[:no_video]
        case input[:type]
        when Type::MASH
          mash = input[:mash]
          Mash.video_ranges(mash).each do |range|
            graphs << __mash_range_graph(input, mash, range, job)
          end
        when Type::VIDEO, Type::IMAGE
          graphs << GraphRaw.new(input)
        end
      end
      graphs
    end
    def self.__mash_range_graph(input, mash, range, job)
      graph = GraphMash.new(job, input, range)
      clips = Mash.clips_in_range(mash, range, Type::VIDEO)
      transition_layer = nil
      trans_clips = []
      clips.each do |clip|
        __copy_raw_from_media(clip, mash)
        if Type::TRANSITION == clip[:type]
          raise(Error::JobInput, "two transitions #{range}") if transition_layer
          transition_layer = graph.add_new_layer(clip)
        elsif clip[:track].zero?
          trans_clips << clip
        end
      end
      if transition_layer
        raise(Error::JobInput, "too many in #{range}") if 2 < trans_clips.length
        trans_clips.each do |clip|
          transition_layer.add_new_layer(clip)
        end
      end
      clips.each do |clip|
        next if transition_layer && clip[:track].zero?
        next unless Type::VISUALS.include?(clip[:type])
        graph.add_new_layer(clip)
      end
      graph
    end
    def self.__copy_raw_from_media(clip, mash)
      if Type::RAW_VISUALS.include?(clip[:type])
        media = Mash.media(mash, clip[:id])
        raise(Error::JobInput, "couldn't find media #{clip[:id]}") unless media
        # media props were copied to clip BEFORE file was cached, so do now
        clip[:cached_file] = media[:cached_file]
        raise("no cached_file #{media}") unless clip[:cached_file]
        clip[:no_video] ||= media[:no_video]
        clip[:dimensions] = media[:dimensions]
        raise("couldn't find dimensions #{media}") unless clip[:dimensions]
      end
    end
    # Transfer - Resolves relative URLs.
    # Default - Job#base_source
    # Types - Just Type::MASH.
    def base_source
      _get(__method__)
    end
    def fill
      _get(__method__)
    end
    # String - How to size in relation to Output#dimensions.
    # Constant - Fill::CROP, Fill::NONE, Fill::SCALE or Fill::STRETCH.
    # Default - Fill::STRETCH.
    # Types - Type::IMAGE and Type::VIDEO.
    def fill=(value)
      _set __method__, value
    end
    def initialize(hash = nil)
      # puts "Input#initialize #{hash}"
      self.class.init_hash hash
      super
    end
    def length
      _get(__method__)
    end
    # Float - Seconds the input appears in the mashup.
    # Default - #duration - #offset
    def length=(value)
      _set __method__, value
    end
    def mash
      _get(__method__)
    end
    # Mash - The mash to include in rendering.
    # Default - nil
    # Types - Just Type::MASH.
    def mash=(value)
      _set __method__, value
    end
    # Transfer - Resolves relative font URLs for modules.
    # Default - Job#module_source
    # Types - Just Type::MASH.
    def module_source
      _get(__method__)
    end
    def offset
      _get(__method__)
    end
    # Float - Seconds to remove from beginning of input.
    # Default - 0.0 means nothing removed.
    # Types - Type::AUDIO and Type::VIDEO.
    def offset=(value)
      _set __method__, value
    end
    def preflight(job = nil)
      super
      mash.preflight job if mash
    end
    def start
      _get(__method__)
    end
    # Float - Seconds from start of mashup to introduce the input.
    # Default - -1.0 means after previous audio in mashup completes.
    # Types - Just Type::AUDIO.
    def start=(value)
      _set __method__, value
    end
  end
end
