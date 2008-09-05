class FlickrDemoController < NSWindowController
  
  attr_accessor :sourcesTableView, :imageBrowserView
  
  def awakeFromNib
    @cache = []
    @imageBrowserView.animates = true
    @imageBrowserView.dataSource = self
    @imageBrowserView.delegate = self
    
    @sources = []
    @sources << Source.new('cat')
    @sourcesTableView.reloadData
    @sourcesTableView.selectRowIndexes(NSIndexSet.indexSetWithIndex(0), byExtendingSelection:false)
    
    NSNotificationCenter.defaultCenter.addObserver self,
      selector:'feedRefreshed:',
      name:PSFeedRefreshingNotification,
      object:nil
  end
  
  # Actions
  
  def addSource(sender)
    row = @sources.size
    @sources << Source.new('dog')
    @sourcesTableView.reloadData
    @sourcesTableView.selectRowIndexes(NSIndexSet.indexSetWithIndex(row), byExtendingSelection:false)
    @sourcesTableView.editColumn(0, row:row, withEvent:nil, select:true)
  end
  
  def removeSource(sender)
    @sources.delete_at @sourcesTableView.selectedRow
    @sourcesTableView.reloadData
    tableViewSelectionDidChange(nil)
  end
  
  def zoomChanged(sender)
    @imageBrowserView.zoomValue = sender.floatValue
  end
  
  def feedRefreshed(notification)
    feed = notification.object
    @results = feed.entryEnumeratorSortedBy(nil).allObjects
    @cache.clear
    @imageBrowserView.reloadData
  end
  
  # table view datasource/delegate
  
  def numberOfRowsInTableView(table)
    @sources ? @sources.size : 0
  end
  
  def tableView(table, objectValueForTableColumn:column, row:row)
    @sources[row].tag
  end

  def tableView(table, setObjectValue:object, forTableColumn:column, row:row)
    source = @sources[row]
    source.tag = object
    refreshImageView(source)
  end

  def tableViewSelectionDidChange(notification)
    refreshImageView @sources[@sourcesTableView.selectedRow]
  end
  
  # Image browser datasource/delegate

  def numberOfItemsInImageBrowser(browser)
    @results ? @results.size : 0
  end
  
  def imageBrowser(browser, itemAtIndex:index)
    photo = @cache[index]
    if photo.nil? 
      entry = @results[index]
      url = entry.content.HTMLString.scan(/<img\s+src="([^"]+)"/)[0][0] # " stupid Xcode
      photo = Photo.new(url)
      @cache[index] = photo
    end
    return photo
  end

  def imageBrowser(browser, cellWasDoubleClickedAtIndex:index)
    NSWorkspace.sharedWorkspace.openURL @cache[index].url
  end
  
  private
  
  def refreshImageView(source)
    if source
      url = NSURL.URLWithString(source.url)
      feed = PSFeed.alloc.initWithURL(url)
      feed.refresh(nil)
    else
      @cache.clear
      @results.clear
      @imageBrowserView.reloadData
    end
  end
end

class Photo
  attr_reader :url
  
  def initialize(url)
    @urlString = url
    @url = NSURL.alloc.initWithString url
  end
  
  # IKImageBrowserItem protocol conformance
  
  def imageUID
    @urlString
  end
    
  def imageRepresentationType
    :IKImageBrowserNSImageRepresentationType
  end
  
  def imageRepresentation    
    @image ||= NSImage.alloc.initByReferencingURL @url
  end
end

class Source
  attr_reader :tag, :url
  
  def initialize(tag)
    self.tag = tag
  end
  
  def tag=(tag)
    @tag = tag
    @url = "http://api.flickr.com/services/feeds/photos_public.gne?tags=#{tag}&lang=en-us&format=rss_200"
  end
end