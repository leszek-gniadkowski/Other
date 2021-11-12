--20130208 LG
--Functions
go

create function dbo.utf16_to_utf8 (@s varbinary(8000),@endian bit) returns varchar(8000) -- @endian 0-little 1-big null-BOM
begin
	if @s is null return null
	if @endian is null and not (convert(char(4),@s,2) = 'FEFF' or convert(char(4),@s,2) = 'FFFE') return null --invalid BOM
	
	declare @n int, @i int,@shex varchar(8000), @r varchar(8000),@b1 char(2),@b2 char(2),@b3 char(2),@b4 char(2),@w1 int,@w2 int, @c int
	set @r = ''
	set @n = 0
	set @shex = convert(varchar(8000),@s,2)
	
	if @endian is null begin
		set @endian = case when convert(char(4),@s,2) = 'FEFF' then 1 else 0 end
		set @shex = stuff(@shex,1,4,'')
	end
	
	while @n / 2 < len(@s) / 2 begin
		set @b1 = substring(@shex,@n * 2 + 1,2)
		set @b2 = substring(@shex,@n * 2 + 3,2)
		set @b3 = substring(@shex,@n * 2 + 5,2)
		set @b4 = substring(@shex,@n * 2 + 7,2)
		if @endian = 1 begin
			set @w1 = convert(binary(2),@b1 + @b2,2)
			set @w2 = convert(binary(2),@b3 + @b4,2)
		end else begin
			set @w1 = convert(binary(2),@b2 + @b1,2)
			set @w2 = convert(binary(2),@b4 + @b3,2)
		end

		if @w1 between 0xD800 and 0xDBFF begin --surrogate pair
			 if @w2 not between 0xDC00 and 0xDFFF begin --invalid trail, ignore unit
				set @c = -1
				set @n = @n + 2
			end else begin --valid pair
				set @c = 0x10000 + (@w1 - 0xD800) * 0x400 + (@w2 - 0xDC00)
				set @n = @n + 4
			end
		end else begin --one unit
			set @c = @w1
			if @c = cast(convert(binary(2),'FFFE',2) as int) set @c = -1 --how to strip invalid utf16 char
			set @n = @n + 2
		end
		set @r = @r + case when @c = -1 then '' --invalid trail unit or strip char
							when @c < 0x80 then cast(char(@c) as varchar)
							when @c < 0x0800 then char(@c / 0x40 & 0x1F | 0xC0) + char(@c & 0x3F | 0x80)
							when @c < 0x010000 then char(@c/0x1000 & 0x0F | 0xE0) + char(@c / 0x40 & 0x3F | 0x80) + char(@c & 0x3F | 0x80) 
							else char(@c/0x40000 & 0x07 | 0xF0) + char(@c/0x1000 & 0x3F | 0x80) + char(@c / 0x40 & 0x3F | 0x80) + char(@c & 0x3F | 0x80) 
							end
	end
return @r
end

go

create function dbo.nvarchar_to_utf8 (@s nvarchar(4000)) returns varchar(8000)
begin
	return dbo.utf16_to_utf8(cast(@s as varbinary(8000)),0)
end

go

--Samples
select dbo.nvarchar_to_utf8(N'aąä')
select dbo.nvarchar_to_utf8(N'ポーランド')
select dbo.nvarchar_to_utf8(N'􏿽') -- last unicode code point U+10FFFD
select dbo.nvarchar_to_utf8(convert(varbinary,'0xFFDBFDDF',1)) -- last unicode code point U+10FFFD
select dbo.utf16_to_utf8(convert(varbinary,'0x00410044',1),1) -- big endian
select dbo.utf16_to_utf8(convert(varbinary,'0xFEFF004100420043',1),null) -- big endian from BOM
