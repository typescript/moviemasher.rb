
module MovieMasher
  # makes directories and sets permissions based on config
  module FileHelper
    def self.safe_path(path, mod = nil)
      options = {}
      mod = MovieMasher.configuration[:chmod_directory_new] if mod.nil?
      if mod
        mod = mod.to_i(8) if mod.is_a?(String)
        options[:mode] = mod
      end
      FileUtils.makedirs(path, options)
    end
  end
end
