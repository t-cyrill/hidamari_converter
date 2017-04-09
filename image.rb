require 'mini_magick'
require 'word_wrap'
require 'word_wrap/core_ext'

# MiniMagick.logger.level = Logger::DEBUG

class AutoMeter
  B5_WIDTH = 2508
  B5_HEIGHT = 3541
  B5_DENSITY = '137.79x137.79'

  NEXT_PAGE_TH_Y = 3200

  MARGIN_X = 160
  MARGIN_Y = 100
  AUTO_MARGIN = 20

  NOMBRE_MARGIN_Y = 100
  NOMBRE_Y = B5_HEIGHT - NOMBRE_MARGIN_Y

  START_X = 100
  START_Y = 100

  TMP_PATH = 'tmp'

  THEME = [
    { fill: '#000000', background: '#ffffff', font: "#{Dir.home}/Library/Fonts/NotoSansCJKjp-Regular.otf" },
    { fill: '#ffffff', background: '#111111', font: "#{Dir.home}/Library/Fonts/ipagp.ttf" },
    { fill: '#000000', background: '#ffffff', font: "#{Dir.home}/Library/Fonts/NotoSansCJKjp-Regular.otf" },
  ]

  ICON_SIZE = 132
  TEXT_POINT = 36

  attr :name
  attr :page
  attr :colorspace
  attr :canvas
  attr :pos_x
  attr :pos_y
  attr :code_mode
  attr :materials
  attr :theme

  def load_materials
    @materials = { ru: [], sy: [] }
    icon_size = ICON_SIZE
    6.times do |i|
      @materials[:ru] << MiniMagick::Image.open("materials/rutee0#{i+1}.png").resize("#{icon_size}x#{icon_size}")
      @materials[:sy] << MiniMagick::Image.open("materials/symfony0#{i+1}.png").resize("#{icon_size}x#{icon_size}")
    end
  end

  def run
    ### load images and text
    load_materials

    text_io = File.open 'text/text.sml'

    page_end = 1000

    x = START_X
    y = START_Y
    @page = 3
    @theme = 0
    code_mode = 0
    line_counter = 0
    text = ''
    text_array = []

    @name = "pages/page#{sprintf('%02d', @page)}.png"
    page_canvas(name: @name, page: @page)
    write

    loop do
      line = text_io.readline.rstrip rescue break
      line_counter = line_counter+1

      @logger.info "Read Pos: #{line_counter}"
      @logger.info "Read Text: #{line}"
      next if line == ''

      seek(x: MARGIN_X)
      if code_mode == 0
        case
        when line[0,3] == '---'
          # Force Next page
          seek(y: B5_HEIGHT)
        when line[0] == '#'
          /(#+) (.*)/.match(line)
          text = $2
          level = $1.size
          # draw text
          text_canvas = heading_canvas(level: level, text: text)
          composite(text_canvas)
          seek(y: @pos_y + text_canvas.height + (AUTO_MARGIN * 2))
        when line[0] == 'S' || line[0] == 'R'
          material = @materials[line[0] == 'S' ? :sy : :ru][(line[1].to_i)-1]
          text = line[3,line.size]
          icon_text(icon_canvas: material, text: text)
          seek(y: @pos_y + material.height + AUTO_MARGIN)
        when line[0,2] == '``'
          @theme = 1
          @theme = 0 if line.strip == '```theme:0'
          @theme = 2 if line.strip == '```theme:2'
          @logger.info "Code Mode: ON"
          code_mode = 1
          text = ''
          next
        end
      else
        if line[0,2] == '``'
          @logger.info "Code Mode: OFF"
          code_mode = 0
        else
          text_array << line
          @logger.info "Current Text: #{text}"
        end

        drawable = auto_text_drawable?(text: text_array.join("\n"), point: TEXT_POINT, width: 2000, theme: @theme)
        @logger.info "code_mode: #{code_mode}"
        @logger.info "drawable: #{drawable.inspect}"
        if code_mode == 0 || !drawable
          #text_array.pop if !drawable
          text = text_array.join("\n")
          next if text == ''
          @logger.info "Draw code text: #{text}"
          height = self.class.auto_text(text, point: TEXT_POINT, width: 2000, theme: @theme).height
          @logger.info "Draw code height: #{height}"
          composite(self.class.auto_text(text, point: TEXT_POINT, width: 2000, height: height + AUTO_MARGIN, theme: @theme))
          text_array = []
          #text_array << line if !drawable
          seek(y: @pos_y + height + (AUTO_MARGIN * 2))
        else
          next
        end

        write
      end

      @logger.info("next: #{next?.inspect}")
      if next?
        break if @page >= page_end # for debug
        @logger.info "Next Page #{@page} -> #{@page+1} (current line: #{line})"
        write

        # Next page
        @page += 1
        @name = "pages/page#{sprintf('%02d', @page)}.png"
        page_canvas(name: @name, page: @page, code_mode: code_mode)
        seek(y: MARGIN_Y)
      end
    end
    write
  rescue EOFError
    @logger.error "EOF reached"
    write
  rescue
    @logger.error "Error happened LINE: #{line_counter}"
    write
    raise
  end

  def initialize(page: 1, colorspace: 'gray')
    @pos_x = 0
    @pos_y = 0
    @page = page
    @colorspace = colorspace
    @logger = Logger.new(STDOUT)
  end

  def heading_canvas(level: 1, text:)
    point = 88 * ((8+1) - level) / 8
    # draw text
    text_canvas = self.class.auto_text(text, point: point)

    width = text_canvas.width
    height = text_canvas.height

    if level <= 2
      new_canvas = MiniMagick::Tool::Convert.new do |i|
        i.size "#{width}x#{height+20}"
        i.gravity 'center'
        i.xc 'white'
        i.stroke 'black'
        i.strokewidth 5
        i.draw "line 0,#{height+10} #{width},#{height+10}"
        i << 'tmp/canvas.png'
      end
      new_canvas = MiniMagick::Image.new 'tmp/canvas.png'
      new_canvas = new_canvas.composite(text_canvas) do |c|
        c.compose 'Over'
        c.geometry "+0+0"
      end
      new_canvas.write 'tmp/canvas.png'
      return new_canvas
    else
      return text_canvas
    end
  end

  def page_canvas(name: nil, page: 1, code_mode: 0)
    @page = page
    @colorspace = colorspace
    @code_mode = code_mode
    bar_x = (@page % 2 == 0) ? MARGIN_X * 2 : (B5_WIDTH - MARGIN_X*2)
    MiniMagick::Tool::Convert.new do |i|
      canvas_default(image: i)
      i.stroke 'black'
      i.strokewidth 5
      i.draw 'line 0,3400 2508,3400'
      i.draw "line #{bar_x},3400 #{bar_x},#{B5_HEIGHT}"
      i << name
    end
    @canvas = MiniMagick::Image.new name
    composite_nombre(point: 40)
    seek(y: MARGIN_Y)
  end

  def composite_nombre(point: 40)
    nombre_x = (@page % 2 == 0) ? MARGIN_X : (B5_WIDTH - MARGIN_X)

    @canvas = @canvas.composite(self.class.auto_text(sprintf("%02d", @page), point: point)) do |c|
      c.compose 'Over'
      c.geometry "+#{nombre_x}+#{NOMBRE_Y}"
    end
    @logger.debug "page: #{@page}"
  end

  def composite(canvas)
    @canvas = @canvas.composite(canvas) do |c|
      c.compose 'Over'
      c.geometry "+#{@pos_x}+#{@pos_y}"
    end
  end

  def seek(x: nil, y: nil)
    @pos_x = x if x
    @pos_y = y if y
  end

  def self.auto_text(text, point: 40, width: nil, height: nil, theme: 0)
    width = B5_WIDTH unless (width || height)

    MiniMagick::Tool::Convert.new do |i|
      i.gravity 'NorthWest'
      i.pointsize "#{point}"
      i.size "#{width}x#{height}"
      i.trim unless (width && height)
      i << '-interline-spacing' << "#{(point)/2}" if theme == 0
      THEME[theme].each { |k, v| i.send(k, v) }
      i.caption "#{text}"
      i << "#{TMP_PATH}/text.png"
    end
    @canvas = MiniMagick::Image.new "#{TMP_PATH}/text.png"
  end

  def icon_text(icon_canvas: , text: )
    pos_x = @pos_x

    # draw icons
    composite(icon_canvas)

    # draw text
    text_canvas = self.class.auto_text(text, point: TEXT_POINT, width: B5_WIDTH - (MARGIN_X*2 + AUTO_MARGIN + ICON_SIZE))

    text_y = (ICON_SIZE - text_canvas.height) / 2
    seek(x: @pos_x + AUTO_MARGIN + ICON_SIZE, y: @pos_y + text_y)
    composite(text_canvas)
    @pos_x = pos_x
  end

  def auto_text_drawable?(text: , point: 40, width: nil, height: nil, theme: nil)
    return true if text == ''
    (@pos_y + self.class.auto_text(text, point: point, width: width, height: height, theme: theme).height) < NEXT_PAGE_TH_Y
  end

  def code_mode=(mode)
    @code_mode = mode
  end

  def code_mode
    @code_mode
  end

  def write
    @canvas.write @name
  end

  def next?
    @pos_y > NEXT_PAGE_TH_Y
  end

  private
  def canvas_default(image:)
    image.size "#{B5_WIDTH}x#{B5_HEIGHT}"
    image.gravity 'center'
    image.xc 'white'
    image.depth 8
    image.units 'PixelsPerCentimeter'
    image.density B5_DENSITY
    image.colorspace @colorspace
  end
end
AutoMeter.new.run

