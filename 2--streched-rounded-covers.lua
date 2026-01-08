--[[ Patch to add rounded corners and stretch covers to uniform size ]]
--

local IconWidget = require("ui/widget/iconwidget")
local logger = require("logger")
local userpatch = require("userpatch")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local ImageWidget = require("ui/widget/imagewidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")

local function patchBookCoverRoundedCornersAndStretch(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
	
	if MosaicMenuItem.patched_streched_rounded_corners then
        return
    end
    MosaicMenuItem.patched_streched_rounded_corners = true
    
    if not MosaicMenuItem then
        logger.warn("Failed to find MosaicMenuItem")
        return
    end

    -- Load rounded corner icons
    local function svg_widget(icon)
        return IconWidget:new({ icon = icon, alpha = true })
    end

    local icons = {
        tl = "rounded.corner.tl",
        tr = "rounded.corner.tr",
        bl = "rounded.corner.bl",
        br = "rounded.corner.br",
    }
    local corners = {}
    for k, name in pairs(icons) do
        corners[k] = svg_widget(name)
        if not corners[k] then
            logger.warn("Failed to load SVG icon: " .. tostring(name))
        end
    end

    local _corner_w, _corner_h
    if corners.tl then
        local sz = corners.tl:getSize()
        _corner_w, _corner_h = sz.w, sz.h
    end

    -- Store original methods
    local orig_MosaicMenuItem_init = MosaicMenuItem.init
    local orig_MosaicMenuItem_paint = MosaicMenuItem.paintTo
    local orig_MosaicMenuItem_free = MosaicMenuItem.free

    -- Override init to intercept and modify cover widget creation
    function MosaicMenuItem:init()
        if orig_MosaicMenuItem_init then
            orig_MosaicMenuItem_init(self)
        end
        
        -- Only process books with covers
        if not self.is_directory and not self.file_deleted then
            -- Get book info
            local bookinfo = require("bookinfomanager"):getBookInfo(self.filepath, self.do_cover_image)
            
            if bookinfo and bookinfo.has_cover and not bookinfo.ignore_cover and bookinfo.cover_bb then
                -- Find the cover widget in the hierarchy
                self:replaceCoverWithStretchedVersion(bookinfo)
            end
        end
    end
    
    -- Method to replace the original cover with a stretched version
    function MosaicMenuItem:replaceCoverWithStretchedVersion(bookinfo)
        -- Navigate to the cover container
        local outer_container = self[1] and self[1][1]
        if not outer_container or not outer_container[1] then
            logger.dbg("Could not find cover container")
            return
        end
        
        local original_cover_widget = outer_container[1]
        
        -- Check if it's already a FrameContainer with an ImageWidget
        local image_widget = nil
        if original_cover_widget[1] and original_cover_widget[1].image then
            -- It's already a FrameContainer with ImageWidget inside
            image_widget = original_cover_widget[1]
        elseif original_cover_widget.image then
            -- It's a direct ImageWidget
            image_widget = original_cover_widget
        else
            logger.dbg("Could not find ImageWidget in cover hierarchy")
            return
        end
        
        -- Get current dimensions
        local current_dimen = outer_container.dimen
        local max_img_w = current_dimen.w
        local max_img_h = current_dimen.h
        local border_size = original_cover_widget.bordersize or 0
        
        -- Calculate scale factor to fill the available space
        local cover_w = bookinfo.cover_w or bookinfo.cover_bb:getWidth()
        local cover_h = bookinfo.cover_h or bookinfo.cover_bb:getHeight()
        local target_w = max_img_w - 2 * border_size
        local target_h = max_img_h - 2 * border_size
        
        local scale_factor
        
        -- Always use math.max to stretch to fill
        scale_factor = math.max(target_w / cover_w, target_h / cover_h)
        
        -- Create stretched ImageWidget
        local stretched_image = ImageWidget:new{
            image = bookinfo.cover_bb,
            scale_factor = scale_factor,
            width = target_w,
            height = target_h,
            stretch_limit_percentage = 30, -- Adjust to need
        }
        
        -- Force render to get final size
        stretched_image:_render()
        local image_size = stretched_image:getSize()
        
        -- Create new FrameContainer with stretched image
        local new_cover_frame = FrameContainer:new{
            width = image_size.w + 2 * border_size,
            height = image_size.h + 2 * border_size,
            margin = 0,
            padding = 0,
            bordersize = border_size,
            dim = self.file_deleted,
            color = self.file_deleted and Blitbuffer.COLOR_DARK_GRAY or nil,
            stretched_image,
        }
        
        -- Store original widget for cleanup
        self._original_cover_widget = original_cover_widget
        
        -- Replace the cover widget
        outer_container[1] = new_cover_frame
        
        logger.dbg("Replaced cover with stretched version, scale: " .. string.format("%.2f", scale_factor))
    end
    
    -- Clean up when item is destroyed
    if orig_MosaicMenuItem_free then
        function MosaicMenuItem:free()
            -- Restore original widget if we replaced it
            if self._original_cover_widget then
                local outer_container = self[1] and self[1][1]
                if outer_container then
                    outer_container[1] = self._original_cover_widget
                end
                self._original_cover_widget = nil
            end
            
            if orig_MosaicMenuItem_free then
                orig_MosaicMenuItem_free(self)
            end
        end
    end

    -- Modified paintTo to add rounded corners
    function MosaicMenuItem:paintTo(bb, x, y)
        -- Call original paintTo
        if orig_MosaicMenuItem_paint then
            orig_MosaicMenuItem_paint(self, bb, x, y)
        end

        -- Locate the cover frame widget
        local target = self[1] and self[1][1] and self[1][1][1]
        
        if target and target.dimen then
            -- Outer frame rect
            local fx = x + math.floor((self.width - target.dimen.w) / 2)
            local fy = y + math.floor((self.height - target.dimen.h) / 2)
            local fw, fh = target.dimen.w, target.dimen.h

            -- Inner content rect = cover area inside padding
            local pad = target.padding or 0
            local inset = 0
            local ix = math.floor(fx + pad + inset)
            local iy = math.floor(fy + pad + inset)
            local iw = math.max(1, fw - 2 * (pad + inset))
            local ih = math.max(1, fh - 2 * (pad + inset))

            local cover_border = Screen:scaleBySize(0.5)
            if not self.is_directory then
                bb:paintBorder(ix, iy, iw, ih, cover_border, Blitbuffer.COLOR_BLACK, 0, false)
            end
        end

        -- Paint rounded corners on the outer frame rect
        if target and target.dimen and not self.is_directory then
            local fx = x + math.floor((self.width - target.dimen.w) / 2)
            local fy = y + math.floor((self.height - target.dimen.h) / 2)
            local fw, fh = target.dimen.w, target.dimen.h

            local TL, TR, BL, BR = corners.tl, corners.tr, corners.bl, corners.br

            -- Helper to get size
            local function _sz(w)
                if w and w.getSize then
                    local s = w:getSize()
                    return s.w, s.h
                end
                return 0, 0
            end

            local tlw, tlh = _sz(TL)
            local trw, trh = _sz(TR)
            local blw, blh = _sz(BL)
            local brw, brh = _sz(BR)

            -- Top-left
            if TL and TL.paintTo then
                TL:paintTo(bb, fx, fy)
            elseif TL then
                bb:blitFrom(TL, fx, fy)
            end
            -- Top-right
            if TR and TR.paintTo then
                TR:paintTo(bb, fx + fw - trw, fy)
            elseif TR then
                bb:blitFrom(TR, fx + fw - trw, fy)
            end
            -- Bottom-left
            if BL and BL.paintTo then
                BL:paintTo(bb, fx, fy + fh - blh)
            elseif BL then
                bb:blitFrom(BL, fx, fy + fh - blh)
            end
            -- Bottom-right
            if BR and BR.paintTo then
                BR:paintTo(bb, fx + fw - brw, fy + fh - brh)
            elseif BR then
                bb:blitFrom(BR, fx + fw - brw, fy + fh - brh)
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchBookCoverRoundedCornersAndStretch)