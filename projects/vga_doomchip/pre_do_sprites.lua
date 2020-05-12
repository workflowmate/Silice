
-- NOTE: uses helper functions from pre_do_textures, include after

print('preparing sprites')

-- -----------------------------------
-- locate a thing in the BSP (returns sub-sector)

function bspLocate(posx,posy)

  queue     = {}
  queue_ptr = 1
  queue[queue_ptr] = root
  queue_ptr = queue_ptr + 1
  while queue_ptr > 1 do
    n = queue[queue_ptr-1]
    queue_ptr = queue_ptr - 1
    if (n&(1<<15)) == 0 then
      lx  = bspNodes[1+n].x
      ly  = bspNodes[1+n].y
      ldx = bspNodes[1+n].dx
      ldy = bspNodes[1+n].dy
      r   = bspNodes[1+n].rchild
      l   = bspNodes[1+n].lchild
      -- which side are we on?
      dx     = posx - lx
      dy     = posy - ly
      csl    = dx * ldy
      csr    = dy * ldx
      if csr > csl then
        -- front
        queue[queue_ptr] = bspNodes[1+n].rchild;
        queue_ptr = queue_ptr + 1     
        queue[queue_ptr] = bspNodes[1+n].lchild;
        queue_ptr = queue_ptr + 1     
      else
        -- back
        queue[queue_ptr] = bspNodes[1+n].lchild;
        queue_ptr = queue_ptr + 1     
        queue[queue_ptr] = bspNodes[1+n].rchild;
        queue_ptr = queue_ptr + 1     
      end
    else
      ssid = (n&(~(1<<15)))
      ss   = ssectors[1+ssid]
      seg  = segs[1+ss.start_seg]
      ldef = lines[1+seg.ldf]  
      if seg.dir == 0 then
        sidedef = sides[1+ldef.right]
      else
        sidedef = sides[1+ldef.left]
      end
      return ssid,sidedef.sec   
    end
  end
  
end

psub,psec = bspLocate(player_start_x,player_start_y)
print('player start in sub-sector ' .. psub .. ' sector ' .. psec)

-- -----------------------------------
-- load sprites in BRAM/BROM

sprites_frames = {
'A1','A2A8','A3A7','A4A6','A5',
'B1','B2B8','B3B7','B4B6','B5',
'C1','C2C8','C3C7','C4C6','C5',
'D1','D2D8','D3D7','D4D6','D5',
'E1','E2E8','E3E7','E4E6','E5',
'F1','F2F8','F3F7','F4F6','F5',
'G1','G2G8','G3G7','G4G6','G5',
--'H0' or 'H1','H2H8','H3H7','H4H6','H5',
--'I0','J0','K0','L0',
--'M0','N0','O0','P0','Q0',
--'R0','S0','T0','U0',
}

sprite_id = 'SPOS'

sprites = {}
id = 1
sprite_col_start = 0
sprite_colptr_offset = 0
for _,sprite_frame in ipairs(sprites_frames) do

  sprite_lump = 'sprites/' .. sprite_id .. sprite_frame .. '.lmp'

  local in_sprite = assert(io.open(findfile(sprite_lump), 'rb'))
  local sz = fsize(in_sprite)
  -- read sprite header
  local sprt_w  = string.unpack('H',in_sprite:read(2))
  local sprt_h  = string.unpack('H',in_sprite:read(2))
  local sprt_lo = string.unpack('h',in_sprite:read(2))
  local sprt_to = string.unpack('h',in_sprite:read(2))  
  print('sprite is ' .. sprt_w .. 'x' .. sprt_h .. ' pixels\n')
  -- read sprite column pointers
  local sprt_cols={}
  for c = 1,sprt_w do
    ptr = string.unpack('I4',in_sprite:read(4))
    sprt_cols[c] = ptr - 4*2 - sprt_w*4 + sprite_colptr_offset
  end
  local sprt_data = {}
  for d = 1,sz - 2*4 - sprt_w*4 do
    sprt_data[d] = string.unpack('B',in_sprite:read(1))
  end
   
  sprites[id] = {
    sprt_w=sprt_w, sprt_h=sprt_h, sprt_lo=sprt_lo, sprt_to=sprt_to,
    sprt_col_start = sprite_col_start,
    sprt_cols=sprt_cols,
    sprt_data=sprt_data
  }

  sprite_colptr_offset = sprite_colptr_offset + #sprt_data
  sprite_col_start = sprite_col_start + #sprt_cols

  id = id + 1

end

print('generating sprite chip code')
local code = assert(io.open(path .. 'spritechip.ice', 'w'))

sprite_bytes = 0

code:write('  brom uint64 sprites_header[] = {\n')
for _,s in ipairs(sprites) do
  code:write('64h')
  code:write(string.format("%04x",s.sprt_w):sub(-4))
  code:write(string.format("%04x",s.sprt_h):sub(-4))
  code:write(string.format("%04x",s.sprt_lo):sub(-4))
  code:write(string.format("%04x",s.sprt_to):sub(-4))
  code:write(',')
  sprite_bytes = sprite_bytes + 4*2;
end
code:write('};\n')

code:write('  brom uint16 sprites_colstarts[] = {\n')
for _,s in ipairs(sprites) do
  code:write('16h' .. string.format("%04x",s.sprt_col_start):sub(-4) .. ',')
  sprite_bytes = sprite_bytes + 2;
end 
code:write('};\n')

code:write('  brom uint16 sprites_colptrs[] = {\n')
for _,s in ipairs(sprites) do
  for _,ptr in pairs(s.sprt_cols) do
    code:write('16h' .. string.format("%04x",ptr):sub(-4) .. ',')
    sprite_bytes = sprite_bytes + 2;
  end
end 
code:write('};\n')

code:write('  brom uint8 sprites_data[] = {\n')
for _,s in ipairs(sprites) do
  for _,ptr in pairs(s.sprt_data) do
    code:write('8h' .. string.format("%02x",ptr):sub(-2) .. ',')
    sprite_bytes = sprite_bytes + 1;
  end
end 
code:write('};\n')

code:close()

print('stored ' .. sprite_bytes .. ' sprite bytes\n')

-- now load file into string
local code = assert(io.open(path .. 'spritechip.ice', 'r'))
spritechip = code:read("*all")
code:close()

