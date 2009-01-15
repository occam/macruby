require "fileutils"

module TempDirHelper
  def ensure_dir!(path)
    FileUtils.mkdir_p(path) unless File.exist?(path)
  end
  
  def setup_temp_dir!
    ensure_dir!(temp_dir)
  end
  
  def teardown_temp_dir!
    FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
  end
  
  def temp_dir(path = nil)
    path.nil? ? TMP_PATH : File.join(TMP_PATH, path)
  end
end