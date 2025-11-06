--[[ User patch: custom rounded progress bar for Project: Title ]]--

local userpatch  = require("userpatch")
local logger     = require("logger")
local Screen     = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local ProgressWidget = require("ui/widget/progresswidget")

--========================== Edit your preferences here ================================
  local BAR_H       = Screen:scaleBySize(9)    -- bar height
  local BAR_RADIUS  = Screen:scaleBySize(3)    -- rounded ends
  local INSET_X     = Screen:scaleBySize(6)    -- from inner cover edges
  local INSET_Y     = Screen:scaleBySize(12)   -- from bottom inner edge
  local GAP_TO_ICON = Screen:scaleBySize(0)    -- gap before corner icon
  local TRACK_COLOR = Blitbuffer.COLOR_GRAY_9  -- bar color
  local FILL_COLOR  = Blitbuffer.COLOR_BLACK   -- fill color
  local ABANDONED_COLOR = Blitbuffer.COLOR_GRAY_6 -- fill when abandoned/paused
--======================================================================================

--========================== Do not modify this section ================================

local function patchCustomProgress(plugin)
  local MosaicMenu        = require("mosaicmenu")
  local MosaicMenuItem    = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")

  -- Capture the shared progress_widget used by base code
  local basePaint         = MosaicMenuItem.paintTo
  local progress_widget   = userpatch.getUpValue(basePaint, "progress_widget")
                            or MosaicMenu.progress_widget

  -- Corner mark size
  local corner_mark_size = userpatch.getUpValue(basePaint, "corner_mark_size") or Screen:scaleBySize(24)

  -- Helper
  local function I(v) return math.floor(v + 0.5) end

  function MosaicMenuItem:paintTo(bb, x, y)
    -- Locate the cover frame
    local target = self[1] and self[1][1] and self[1][1][1] or nil

    -- disable progress_widget temporarily
    local orig_pw_paint = nil
    if progress_widget and progress_widget.paintTo then
      orig_pw_paint = progress_widget.paintTo
      progress_widget.paintTo = function() end
    end

    -- suspend base percent so it won't render percent text
    local pf = self.percent_finished
    self.percent_finished = nil

    -- Suppress the abandoned status corner mark during base paint
    local was_abandoned = (self.status == "abandoned")
    local saved_status, saved_been, saved_hint
    if was_abandoned then
      saved_status = self.status
      saved_been   = self.been_opened
      saved_hint   = self.do_hint_opened
      -- Clear status & hint flags so the base code won't draw the abandoned badge
      self.status        = nil
      self.been_opened   = false
      self.do_hint_opened = false
    end
    
    -- Paint everything else normally once
    local ok, err = pcall(basePaint, self, bb, x, y)
    
    -- Restore original fields
    self.percent_finished = pf
    if was_abandoned then
      self.status        = saved_status
      self.been_opened   = saved_been
      self.do_hint_opened = saved_hint
    end
    
    if not ok then error(err) end

    -- Our custom bar
    if not target or not target.dimen or not pf then return end

    -- Outer cover rect; then inner content rect
    local fx = x + math.floor((self.width  - target.dimen.w) / 2)
    local fy = y + math.floor((self.height - target.dimen.h) / 2)
    local fw, fh = target.dimen.w, target.dimen.h

    local b   = target.bordersize or 0
    local pad = target.padding    or 0
    local ix  = fx + b + pad
    local iy  = fy + b + pad
    local iw  = fw - 2 * (b + pad)
    local ih  = fh - 2 * (b + pad)

    -- Compute bar horizontal span
    local left  = ix + INSET_X
    local right = ix + iw - INSET_X

    -- If a status icon will be present, shorten the bar
    local has_corner_icon = (self.been_opened or self.do_hint_opened) and (self.status == "reading" or self.status == "complete" or self.status == "abandoned")
    if has_corner_icon then
      right = right - (corner_mark_size + GAP_TO_ICON)
    end

    -- Vertical placement
    local bar_w = math.max(1, right - left)
    local bar_h = BAR_H
    local bar_x = I(left)
    local bar_y = I(iy + ih - INSET_Y - bar_h)

    -- Background
    bb:paintRoundedRect(bar_x, bar_y, bar_w, bar_h, TRACK_COLOR, BAR_RADIUS)

    -- Fill
    local p = math.max(0, math.min(1, pf))
    local fw_w = math.max(1, math.floor(bar_w * p + 0.5))
    local fill_color = (self.status == "abandoned") and ABANDONED_COLOR or FILL_COLOR
    bb:paintRoundedRect(bar_x, bar_y, fw_w, bar_h, fill_color, BAR_RADIUS)
  end
end
userpatch.registerPatchPluginFunc("coverbrowser", patchCustomProgress)