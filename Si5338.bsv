import Uart::*;
import GetPut::*;
import I2CMaster::*;
import StmtFSM::*;
import RegFile::*;
import Clocks::*;
import FIFO::*;
import BlueUtils::*;


//typedef 115200 BaudRate;
//typedef 50_000_000 ClockFreq;
Bit#(7) si5338_i2c_addr=7'h70;
String reg_file_name="si5338_reg.mem";

`define DEBUG_OUT
Bit#(8) los_mask=8'h04;
Bit#(8) lock_mask=8'h15;

function Int#(32) test(String s);
    return fromInteger(stringLength(s));
endfunction

interface Si5338#(numeric type baud_rate, numeric type clock_freq_Hz);
    interface UartTxWires#(baud_rate, clock_freq_Hz) uart_tx_wires;
    interface I2CMasterWires i2c_master_wires;
endinterface



typedef struct{
    Bit#(8) addr;
    Bit#(8) reg_value;
    Bit#(8) mask;
}Si5338Reg deriving(Eq, Bits);

instance FShow#(Si5338Reg);
    function Fmt fshow(Si5338Reg v);
        return ($format("%2h%2h%2h", v.addr, v.reg_value, v.mask));
    endfunction
endinstance


module mkSi5338(Si5338#(baud_rate, clock_freq_Hz));
    RegFile#(Bit#(9), Si5338Reg) reg_data <-mkRegFileLoad(reg_file_name,0, 349);
    UartTx#(baud_rate, clock_freq_Hz) tx <- mkUartTx;
    I2CMaster i2cm<-mkI2CMaster(7);
    Clock current_clk<-exposeCurrentClock();
    Reset current_rst<-exposeCurrentReset();
    
    Reg#(UInt#(32)) cnt_print<-mkReg(0);

`ifdef DEBUG_OUT
    Reg#(Int#(16)) print_str_loop_idx<-mkReg(0);
`endif
    Reg#(Bit#(7)) scan_addr<-mkReg(0);
    Reg#(Bool) ack_received<-mkReg(False);
    Reg#(Bit#(8)) received_data<-mkReg(0);
    Reg#(Bit#(8)) reg_addr<-mkReg(0);
    Reg#(Bit#(9)) reg_idx<-mkReg(0);
    Reg#(Si5338Reg) reg_data1<-mkReg(?);
    Reg#(Bit#(8)) reg_new_data<-mkReg(?);
    Reg#(UInt#(26)) wait_counter<-mkReg(0);

`ifdef DEBUG_OUT
    function Stmt print_str(String s);
        return seq
            for(print_str_loop_idx<=0;print_str_loop_idx<fromInteger(stringLength(s));print_str_loop_idx<=print_str_loop_idx+1)
                tx.tx.put(fromInteger(charToInteger(s[print_str_loop_idx])));
        endseq;
    endfunction

    function Stmt print_line_break();
        return seq
            tx.tx.put(13);//\r
            tx.tx.put(10);//\n
        endseq;
    endfunction

    function Stmt print_data(Bit#(8) data);
        let content_to_print=int8ToString(data);
        return seq
            tx.tx.put(content_to_print[15:8]);
            tx.tx.put(content_to_print[7:0]);
        endseq;
    endfunction

    function Stmt print_word(Bit#(32) data);
        let content_to_print=int32ToString(data);
        return seq
            tx.tx.put(content_to_print[63:56]);
            tx.tx.put(content_to_print[55:48]);
            tx.tx.put(content_to_print[47:40]);
            tx.tx.put(content_to_print[39:32]);
            tx.tx.put(content_to_print[31:24]);
            tx.tx.put(content_to_print[23:16]);
            tx.tx.put(content_to_print[15:8]);
            tx.tx.put(content_to_print[7:0]);
        endseq;
    endfunction


    function Stmt print_addr(Bit#(7) addr);
        let addr8={1'b0, addr};
        return print_data(addr8);
    endfunction
`endif

    function Stmt read_reg_data(Bit#(7) addr, Bit#(8) reg_addr1);
        return seq
        //print_str("=======");
        //print_line_break();
        i2cm.ops.request.put(tagged Start);
        i2cm.ops.request.put(tagged Write ({addr,0}));
        i2cm.ops.request.put(tagged GetAck);
        action
        let r<-i2cm.ops.response.get();
        //if (tagged Ack==r) print_str("a");
            case(r) matches
                tagged Ack: ack_received<=True;
                default: ack_received<=False;
            endcase
        endaction

        //if (ack_received) print_str("Ack received");
        //else print_str("NACK received");
        //print_line_break();

        i2cm.ops.request.put(tagged Write reg_addr1);
        i2cm.ops.request.put(tagged GetAck);
        i2cm.ops.request.put(tagged Stop);
        
        action
        let r<-i2cm.ops.response.get();
        //if (tagged Ack==r) print_str("a");
            case(r) matches
                tagged Ack: ack_received<=True;
                default: ack_received<=False;
            endcase
        endaction

        //if (ack_received) print_str("Ack received");
        //else print_str("NACK received");
        //print_line_break();

        i2cm.ops.request.put(tagged Start);
        i2cm.ops.request.put(tagged Write ({addr,1}));
        i2cm.ops.request.put(tagged GetAck);

        action
        let r<-i2cm.ops.response.get();
        //if (tagged Ack==r) print_str("a");
            case(r) matches
                tagged Ack: ack_received<=True;
                default: ack_received<=False;
            endcase
        endaction

        //if (ack_received) print_str("Ack received");
        //else print_str("NACK received");
        //print_line_break();
        
        //i2cm.ops.request.put(Stop, 0);
        i2cm.ops.request.put(tagged Read);
        i2cm.ops.request.put(tagged PutNAck);
        action 
            let x1<- i2cm.ops.response.get();
            case (x1) matches
                tagged Received .x :received_data<=x;
            endcase
        endaction
        i2cm.ops.request.put(tagged Stop);
        //print_data(received_data);
        endseq;
    endfunction

    function Stmt write_reg_data(Bit#(7) addr, Bit#(8) reg_addr1, Bit#(8) data);
        return seq
        i2cm.ops.request.put(tagged Start);
        i2cm.ops.request.put(tagged Write ({addr,0}));
        i2cm.ops.request.put(tagged GetAck);
        action
        let r<-i2cm.ops.response.get();
        //if (tagged Ack==r) print_str("a");
            case(r) matches
                tagged Ack: ack_received<=True;
                default: ack_received<=False;
            endcase
        endaction

        //if (ack_received) print_str("Ack received");
        //else print_str("NACK received");
        //print_line_break();

        i2cm.ops.request.put(tagged Write reg_addr1);
        i2cm.ops.request.put(tagged GetAck);
        
        action
        let r<-i2cm.ops.response.get();
        //if (tagged Ack==r) print_str("a");
            case(r) matches
                tagged Ack: ack_received<=True;
                default: ack_received<=False;
            endcase
        endaction

        //if (ack_received) print_str("Ack received");
        //else print_str("NACK received");
        //print_line_break();
        i2cm.ops.request.put(tagged Write data);
        i2cm.ops.request.put(tagged GetAck);

        action
        let r<-i2cm.ops.response.get();
        //if (tagged Ack==r) print_str("a");
            case(r) matches
                tagged Ack: ack_received<=True;
                default: ack_received<=False;
            endcase
        endaction

        //if (ack_received) print_str("Ack received");
        //else print_str("NACK received");
        //print_line_break();

        i2cm.ops.request.put(tagged Stop);
        endseq;
    endfunction

    function Stmt is_slave_alive(Bit#(7) addr);
        return seq
            i2cm.ops.request.put(tagged Start);
            i2cm.ops.request.put(tagged Write ({addr,0}));
            i2cm.ops.request.put(tagged GetAck);
            i2cm.ops.request.put(tagged Stop);
            action
                let r<-i2cm.ops.response.get();
                //if (tagged Ack==r) print_str("a");
                    case(r) matches
                        tagged Ack: ack_received<=True;
                        default: ack_received<=False;
                    endcase
                endaction

`ifdef DEBUG_OUT
            if(ack_received) seq
                print_str("Slave: ");
                print_addr(addr);
                print_str(" replied");
                print_line_break();
            endseq
`endif
        endseq;
    endfunction



    mkAutoFSM(seq
        //while(True)seq
        for(scan_addr<=0;scan_addr!=7'h7f;scan_addr<=scan_addr+1)
            is_slave_alive(scan_addr);

        write_reg_data(si5338_i2c_addr, 8'hff, 0);
        write_reg_data(si5338_i2c_addr, 230, 8'h10);
        write_reg_data(si5338_i2c_addr, 241, 8'he5);
        for(reg_idx<=0; reg_idx!=349; reg_idx<=reg_idx+1) seq
            reg_data1<=reg_data.sub(reg_idx);
            read_reg_data(si5338_i2c_addr, reg_data1.addr);
`ifdef DEBUG_OUT
            print_data(reg_data1.addr);
            print_str(":");
            print_data(received_data);
            print_line_break();
`endif
            action
                let mask1=reg_data1.mask;
                let clear_reg_data=received_data & (~mask1);
                let clear_new_data=reg_data1.reg_value&mask1;
                let combined=clear_reg_data | clear_new_data;
                reg_new_data<=combined;
            endaction
`ifdef DEBUG_OUT
            print_str("Writting:");
            print_data(reg_new_data);
`endif
            write_reg_data(si5338_i2c_addr, reg_data1.addr, reg_new_data);
            read_reg_data(si5338_i2c_addr, reg_data1.addr);
`ifdef DEBUG_OUT
            print_line_break();
            print_str("Written data: ");
            print_data(reg_data1.addr);
            print_str(":");
            print_data(received_data);
            print_line_break();
`endif
        endseq

        read_reg_data(si5338_i2c_addr, 218);
        received_data<=received_data&los_mask;
        while(received_data!=0)seq
            read_reg_data(si5338_i2c_addr, 218);
            received_data<=received_data&los_mask;
        endseq
        write_reg_data(si5338_i2c_addr, 8'hff, 0);
        read_reg_data(si5338_i2c_addr, 49);
        write_reg_data(si5338_i2c_addr, 49, received_data&8'h7f);
        write_reg_data(si5338_i2c_addr, 246, 2);
        write_reg_data(si5338_i2c_addr, 241, 8'h65);
        write_reg_data(si5338_i2c_addr, 241, 8'h65);
        write_reg_data(si5338_i2c_addr, 241, 8'h65);
        read_reg_data(si5338_i2c_addr, 218);
        received_data<=received_data&los_mask;
        while(received_data!=0)seq
            read_reg_data(si5338_i2c_addr, 218);
            received_data<=received_data&los_mask;
        endseq
        read_reg_data(si5338_i2c_addr, 235);
        write_reg_data(si5338_i2c_addr, 45, received_data);
        read_reg_data(si5338_i2c_addr, 236);
        write_reg_data(si5338_i2c_addr, 46, received_data);
        read_reg_data(si5338_i2c_addr, 47);
        write_reg_data(si5338_i2c_addr, 47, received_data&8'hfc);
        read_reg_data(si5338_i2c_addr, 49);
        write_reg_data(si5338_i2c_addr, 49, received_data&8'h80);


        
        write_reg_data(si5338_i2c_addr, 8'hf1, 8'h65);
        
        //write_reg_data(si5338_i2c_addr, 8'hf1, 8'h65);
        write_reg_data(si5338_i2c_addr, 8'he6, 8'h00);

`ifdef DEBUG_OUT
        print_str("dumping:");
        print_line_break();
`endif
        write_reg_data(si5338_i2c_addr, 8'hff, 0);
        for(reg_idx<=0; reg_idx!=349; reg_idx<=reg_idx+1) seq
            reg_data1<=reg_data.sub(reg_idx);
            if(reg_data1.addr==8'hff) write_reg_data(si5338_i2c_addr, 8'hff, 1);
            read_reg_data(si5338_i2c_addr, reg_data1.addr);
            //print_str(reg_data1.addr==1?"1":"0");
`ifdef DEBUG_OUT
            print_data(reg_data1.addr);
            print_str(" : ");
            print_data(received_data);
            print_line_break();
`endif
        endseq
`ifdef DEBUG_OUT
        print_str("done");
        print_line_break();


        while (True)seq
            read_reg_data(si5338_i2c_addr, 8'hda);
            if(received_data[4]==0) seq
                print_str("locked");
            endseq
            else seq
                print_str("not locked");
            endseq
            print_line_break();
        endseq
`endif
        

        /*
        while(True)
        seq
            for(reg_addr<=0; reg_addr!=8'hff; reg_addr<=reg_addr+1)
            seq
                //reg_addr<=8;
                read_reg_data(si5338_i2c_addr, reg_addr);
                print_data(reg_addr);
                print_str(":");
                print_data(received_data);
                print_line_break();
            endseq
            read_reg_data(si5338_i2c_addr, 8'hff);
            print_data(reg_addr);
            print_str(":");
            print_data(received_data);
            print_line_break();
        endseq*/
        //read_reg_data(si5338_i2c_addr, 0);

            //print_str("abcbcdefgh");
        //endseq
        //
    endseq);

    
    interface UartTxWires uart_tx_wires=tx.wires;
    interface I2CMasterWires i2c_master_wires=i2cm.wires;
endmodule

(*synthesize*)
module mkSi5338_115200_50M(Si5338#(115200, 50_000_000));
    Si5338#(115200, 50_000_000) inst<-mkSi5338;
    return inst;
endmodule
