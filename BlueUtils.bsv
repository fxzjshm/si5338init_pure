function Bit#(8) int4ToChar(Bit#(4) x);
    return case (x) matches
        0: fromInteger(charToInteger("0"));
        1: fromInteger(charToInteger("1"));
        2: fromInteger(charToInteger("2"));
        3: fromInteger(charToInteger("3"));
        4: fromInteger(charToInteger("4"));
        5: fromInteger(charToInteger("5"));
        6: fromInteger(charToInteger("6"));
        7: fromInteger(charToInteger("7"));
        8: fromInteger(charToInteger("8"));
        9: fromInteger(charToInteger("9"));
        4'ha: fromInteger(charToInteger("a"));
        4'hb: fromInteger(charToInteger("b"));
        4'hc: fromInteger(charToInteger("c"));
        4'hd: fromInteger(charToInteger("d"));
        4'he: fromInteger(charToInteger("e"));
        4'hf: fromInteger(charToInteger("f"));
    endcase;
endfunction

function Bit#(16) int8ToString(Bit#(8) x);
    return {int4ToChar(x[7:4]), int4ToChar(x[3:0])};
endfunction

function Bit#(32) int16ToString(Bit#(16) x);
    return {int8ToString(x[15:8]), int8ToString(x[7:0])};
endfunction

function Bit#(64) int32ToString(Bit#(32) x);
    return {int16ToString(x[31:16]), int16ToString(x[15:0])};
endfunction
