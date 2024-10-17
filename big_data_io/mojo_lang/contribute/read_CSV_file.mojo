# just a funtion read massive CSV files  
# @todo -> improve that code
# https://mzaks.medium.com/simple-csv-parser-in-mojo-3555c13fb5c8


from DType import DType
from Functional import vectorize
from Intrinsics import compressed_store
from Math import iota, any_true, reduce_bit_count
from Memory import *
from Pointer import DTypePointer
from String import String, ord
from TargetInfo import dtype_simd_width
from Vector import DynamicVector

alias simd_width_u8 = dtype_simd_width[DType.ui8]()

struct SimdCsvTable:
    var inner_string: String
    var starts: DynamicVector[Int]
    var ends: DynamicVector[Int]
    var column_count: Int
    
    fn __init__(inout self, owned s: String):
        self.inner_string = s
        self.starts = DynamicVector[Int](10)
        self.ends = DynamicVector[Int](10)
        self.column_count = -1
        self.parse()
    
    @always_inline
    fn parse(inout self):
        let QUOTE = ord('"')
        let COMMA = ord(',')
        let LF = ord('\n')
        let CR = ord('\r')
        let p = DTypePointer[DType.si8](self.inner_string.buffer.data)
        let string_byte_length = len(self.inner_string)
        var in_quotes = False
        self.starts.push_back(0)
        
        @always_inline
        @parameter
        fn find_indexies[simd_width: Int](offset: Int):
            let chars = p.simd_load[simd_width](offset)
            let quotes = chars == QUOTE
            let commas = chars == COMMA
            let lfs = chars == LF
            let all_bits = quotes | commas | lfs
            
            let offsets = iota[simd_width, DType.ui8]()
            let sp: DTypePointer[DType.ui8] = stack_allocation[simd_width, UI8, simd_width]()
            compressed_store(offsets, sp,  all_bits)
            let all_len = reduce_bit_count(all_bits)
            
            let crs_ui8 = (chars == CR).cast[DType.ui8]()
            let lfs_ui8 = lfs.cast[DType.ui8]()

            for i in range(all_len):
                let index = sp.load(i).to_int()
                if quotes[index]:
                    in_quotes = not in_quotes
                    continue
                if in_quotes:
                    continue
                let current_offset = index + offset
                self.ends.push_back(current_offset - (lfs_ui8[index] * crs_ui8[index - 1]).to_int())
                self.starts.push_back(current_offset + 1)
                if self.column_count == -1 and lfs[index]:
                    self.column_count = len(self.ends)
            
        vectorize[simd_width_u8, find_indexies](string_byte_length)
        self.ends.push_back(string_byte_length)
    
    fn get(self, row: Int, column: Int) -> String:
        if column >= self.column_count:
            return ""
        let index = self.column_count * row + column
        if index >= len(self.ends):
            return ""
        return self.inner_string[self.starts[index]:self.ends[index]]


# source
# https://mzaks.medium.com/simple-csv-parser-in-mojo-3555c13fb5c8
