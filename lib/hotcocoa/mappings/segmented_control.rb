HotCocoa::Mappings.map :segmented_control => :NSSegmentedControl do
  
  def init_with_options(segmented_control, options)
    segmented_control.initWithFrame options.delete(:frame)
  end
  
  custom_methods do
    
    class Segment
      attr_reader :number, :control
      def initialize(control, number)
        @number = number
        @control = control
      end
      
      def width
        control.widthForSegment(number)
      end
      
      def width=(width)
        control.setWidth(width, forSegment:number)
      end
      
      def label
        control.labelForSegment(number)
      end
      
      def label=(label)
        control.setLabel(label, forSegment:number)
      end
      
      def image
        control.imageForSegment(number)
      end
      
      def image=(image)
        control.setImage(image, forSegment:number)
      end
      
      def menu
        control.menuForSegment(number)
      end
      
      def menu=(menu)
        control.setMenu(menu, forSegment:number)
      end
      
      def selected?
        control.isSelectedForSegment(number)
      end
      
      def selected=(value)
        control.setSelected(value, forSegment:number)
      end
      
      def enabled?
        control.isEnabledForSegment(number)
      end
      
      def enabled=(value)
        control.setEnabled(value, forSegment:number)
      end
    end
    
    def segments=(segments)
      segments.each do |segment|
        self << segment
      end
    end

    def <<(data)
      setSegmentCount(segmentCount+1)
      segment = Segment.new(self, segmentCount-1)
      data.each do |key, value|
        segment.send("#{key}=", value)
      end
    end
    
    def [](segment_number)
      Segment.new(self, segment_number)
    end
    
    def select(segment_number)
      setSelectedSegment(segment_number)
    end
    
    def selected_segment
      Segment.new(self, selectedSegment)
    end

  end
  
end
