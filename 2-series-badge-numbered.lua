--[[ Patch to add series indicator to the right side of the book cover ]]--
local userpatch = require("userpatch")
local logger = require("logger")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Screen = require("device").screen
local Size = require("ui/size")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")

--========================== [[Edit your preferences here]] ================================
local font_size = 11						-- Adjust from 0 to 1
local border_thickness = 1 					-- Adjust from 0 to 5
local border_corner_radius = 9 			-- Adjust from 0 to 20
local text_color = Blitbuffer.colorFromString("#000000") 	-- Choose your desired color
local border_color = Blitbuffer.colorFromString("#000000")-- Choose your desired color
local background_color = Blitbuffer.COLOR_GRAY_E-- Choose your desired color

--==========================================================================================

local function patchAddSeriesIndicator(plugin)
    -- Grab Cover Grid mode and the individual Cover Grid items
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")

    -- Store the original paintTo method first
    local orig_MosaicMenuItem_paint = MosaicMenuItem.paintTo

    -- Override paintTo method
    function MosaicMenuItem:paintTo(bb, x, y)
        -- Call the original paintTo method to draw the cover normally
        orig_MosaicMenuItem_paint(self, bb, x, y)
        
        -- Get the cover image widget (target) and dimensions
        local target = self[1][1][1]
        if not target or not target.dimen then
            return
        end
        -- Use the same corner_mark_size as the original code for consistency
        local corner_mark_size = Screen:scaleBySize(10)	
		
		-- Check if book has series info and set flag
		if not self.is_directory and not self.file_deleted then
			local bookinfo = require("bookinfomanager"):getBookInfo(self.filepath, self.do_cover_image)
			if bookinfo and bookinfo.series and bookinfo.series_index then
				self.in_series = true
				self.series_text = "#"..bookinfo.series_index
			end
		end
		
		-- Draw series indicator
		if self.in_series and self.series_text then
			local target = self[1][1][1]
			if target and target.dimen then               
				local d_w = math.ceil(target.dimen.w/5)
				local d_h = math.ceil(target.dimen.h/10)
				
				local ix

				if BD.mirroredUILayout() then
					ix = -math.floor(d_w)  -- Half outside on left side
					local x_overflow_left = x - target.dimen.x + ix
					if x_overflow_left > 0 then
						self.refresh_dimen = self[1].dimen:copy()
						self.refresh_dimen.x = self.refresh_dimen.x - x_overflow_left
						self.refresh_dimen.w = self.refresh_dimen.w + x_overflow_left
					end
					
				else
					ix = target.dimen.w - math.floor(d_w)  -- Half outside on right side
					local x_overflow_right = target.dimen.x + ix + d_w - x - self.dimen.w
					if x_overflow_right > 0 then
						self.refresh_dimen = self[1].dimen:copy()
						self.refresh_dimen.w = self.refresh_dimen.w + x_overflow_right
					end
				end
				
				-- Move down on y axis
				local iy = 0
				
				-- Add series text widget
				local series_text = TextWidget:new{
					text = self.series_text,
					face = Font:getFace("cfont", font_size),
					bold = true,
					fgcolor = text_color,
				}
				
				local series_badge = FrameContainer:new{
					linesize = Screen:scaleBySize(2),
                    radius = Screen:scaleBySize(border_corner_radius),
                    color = border_color,
                    bordersize = border_thickness,
                    background = background_color,
                    padding = Screen:scaleBySize(2),
                    margin = 0,
                    series_text,
                }
				
				local text_width = series_text:getSize().w
				local text_height = series_text:getSize().h
				
				-- Calculate center position within the indicator (adjust for the new positioning)
				local text_x = target.dimen.x + ix + (d_w - text_width) / 2
				local text_y = target.dimen.y + iy + (d_h - text_height) / 2
				
				-- Paint the text widget
				series_badge:paintTo(bb, text_x, text_y)
			end
		end
    end
end
userpatch.registerPatchPluginFunc("coverbrowser", patchAddSeriesIndicator)