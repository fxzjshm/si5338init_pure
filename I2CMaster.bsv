import StmtFSM::*;
import GetPut::*;
import BlueUtils::*;
interface I2CMasterWires;
(*always_enabled,always_ready*)
    method Bit#(1) scl_out;
(*always_enabled,always_ready*)
    method Bit#(1) sda_out;
(*always_enabled,always_ready*)
    method Action sda_in(Bit#(1) x);
(*always_enabled,always_ready*)
    method Bit#(1) oe_out;
endinterface


/*
typedef enum{
    Start,
    Write,
    Read,
    GetAck,
    PutAck,
    Stop
} Cmd deriving(Eq, FShow, Bits);
*/

typedef union tagged{
    void Start;
    Bit#(8) Write;
    void Read;
    void GetAck;
    void PutAck;
    void PutNAck;
    void Stop;
}Request deriving(Eq, FShow, Bits);

typedef union tagged{
    void Ack;
    void NAck;
    Bit#(8) Received;
}Response deriving(Eq, FShow, Bits);


interface I2CMasterOperation;
    //method Action put_cmd(Request req);
    //method Bit#(8) get_result;
    interface Put#(Request) request;
    interface Get#(Response) response;
    (*always_enabled,always_ready*)
    method Bool is_busy;
endinterface


interface I2CMaster;
    interface I2CMasterWires wires;
    interface I2CMasterOperation ops;
endinterface



module mkI2CMaster#(Integer log2_scl2clk_ratio)(I2CMaster);
    Reg#(Bit#(1)) scl_state <-mkReg(1);
    Reg#(Bit#(1)) sda_out_state <-mkReg(1);
    Reg#(Bit#(8)) out_buf <-mkReg('h55);
    Reg#(Bit#(8)) in_buf <-mkReg(0);
    Reg#(Bit#(1)) ack<-mkReg(0);
    Reg#(Bit#(1)) oe_state<-mkReg(1);
    Reg#(Bit#(1)) sda_in_state <- mkReg(1);
    Reg#(Bit#(1)) last_bit_in<-mkReg(1);
    
    Reg#(Request) last_req<-mkReg(?);

    
    

    function Stmt send_bit(Bit#(1) x);
        Stmt result=seq
            action
            sda_out_state<=x;
            oe_state<=1;
            endaction
            repeat(1<<(log2_scl2clk_ratio-2)) action
                scl_state<=0;
            endaction
            repeat(1<<(log2_scl2clk_ratio-1)) action
                scl_state<=1;
            endaction
            repeat(1<<(log2_scl2clk_ratio-2)) action
                scl_state<=0;
            endaction
        endseq;
        return result;
    endfunction

    Stmt recv_bit=seq
        oe_state<=0;
        repeat(1<<(log2_scl2clk_ratio-2)) action
            scl_state<=0;
        endaction
        repeat(1<<(log2_scl2clk_ratio-2)) action
            scl_state<=1;
        endaction
        last_bit_in <= sda_in_state;
        repeat(1<<(log2_scl2clk_ratio-2)) action
            scl_state<=1;
        endaction
        repeat(1<<(log2_scl2clk_ratio-2)) action
            scl_state<=0;
        endaction
    endseq;


    FSM send_fsm<-mkFSM(
        seq
            repeat(8)
            seq
                send_bit(out_buf[7]);
                out_buf<={out_buf[6:0], 1};
            endseq
        endseq
    );

    FSM read_fsm<-mkFSM(
        seq
            oe_state<=0;
            repeat(8)
            seq
                recv_bit;
                in_buf<={in_buf[6:0], last_bit_in};
            endseq
        endseq
    );

    FSM start_fsm<-mkFSM(
        seq
            repeat(1<<(log2_scl2clk_ratio-2)) action
                sda_out_state<=1;
                oe_state<=1;             
            endaction

            repeat(1<<(log2_scl2clk_ratio-2)) action
                scl_state<=1;                
            endaction
            repeat(1<<(log2_scl2clk_ratio-2)) action
                sda_out_state<=0;
            endaction
            repeat(1<<(log2_scl2clk_ratio-2)) action
                scl_state<=0;
            endaction
        endseq
    );

    FSM get_ack_fsm<-mkFSM(
        seq
            recv_bit;
            $display("ack=", last_bit_in);
            ack<=~last_bit_in;
        endseq
    );

    FSM put_ack_fsm<-mkFSM(
        seq
            send_bit(0);
        endseq
    );

    FSM put_nack_fsm<-mkFSM(
        seq
            send_bit(1);
        endseq
    );

    FSM stop_fsm<-mkFSM(
        seq
            repeat(1<<(log2_scl2clk_ratio-2)) action
                sda_out_state<=0;
                scl_state<=0;
                oe_state<=1;
            endaction
            repeat(1<<(log2_scl2clk_ratio-2)) action
                scl_state<=1;
            endaction
            repeat(1<<(log2_scl2clk_ratio-2)) action
            sda_out_state<=1;
            endaction
        endseq
    );

    

    Bool idle=  send_fsm.done()&&
                read_fsm.done()&&
                start_fsm.done()&&
                get_ack_fsm.done()&&
                put_ack_fsm.done()&&
                put_nack_fsm.done()&&
                stop_fsm.done();
    
    interface I2CMasterOperation ops;
        interface Put request;
            method Action put(Request req) if (idle);
                //last_cmd<=cmd;
                case (req) matches
                    tagged Start : begin
                        start_fsm.start();
                    end
                    tagged Write .p: begin
                        last_req<=req;
                        out_buf <= p;
                        send_fsm.start();
                    end
                    tagged Read: begin
                        last_req<=req;
                        read_fsm.start();
                    end
                    tagged GetAck: begin
                        get_ack_fsm.start();
                    end
                    tagged PutAck: begin
                        put_ack_fsm.start();
                    end
                    tagged PutNAck: begin
                        put_nack_fsm.start();
                    end
                    tagged Stop: begin
                        stop_fsm.start();
                    end

                endcase
            endmethod
        endinterface


        interface Get response;
            method ActionValue#(Response) get() if(
                case (last_req) matches
                    tagged Write .p: True;
                    tagged Read : True;
                    default: False;
                endcase
            );
                return case (last_req) matches
                    tagged Write .p: ack==1?(tagged Ack):(tagged NAck);
                    tagged Read: tagged Received in_buf;
                    default: tagged NAck;
                endcase;
            endmethod
        endinterface
        method Bool is_busy=!idle;
    endinterface

    interface I2CMasterWires wires;
        method Bit#(1) scl_out=scl_state;
        method Bit#(1) sda_out=sda_out_state;
        method Bit#(1) oe_out=oe_state;
        method Action sda_in(Bit#(1) x);
            sda_in_state<=x;
        endmethod
        
    endinterface
    
endmodule





(* synthesize *)
module mkI2CMaster5(I2CMaster);
    I2CMaster i2cm<-mkI2CMaster(5);
    return i2cm;
endmodule

interface I2CScanner;
    interface I2CMasterWires wires;
    method Bit#(7) last_responsed;
endinterface

(*synthesize*)
module mkI2CScanner(I2CScanner);
    I2CMaster i2cm<-mkI2CMaster(10);
    Reg#(Bit#(7)) _last_responsed<-mkReg(0);
    Reg#(Bit#(7)) current_addr<-mkReg(0);
    mkAutoFSM(
        seq
            while(True)seq
                i2cm.ops.request.put(tagged Start);
                i2cm.ops.request.put(tagged Write ({current_addr,0}));
                i2cm.ops.request.put(tagged GetAck);
                i2cm.ops.request.put(tagged Stop);
                action
                    let x<-i2cm.ops.response.get();
                    if (x==tagged Ack) _last_responsed<=current_addr;
                endaction
                current_addr<=current_addr+1;
            endseq
        endseq
    );


    interface I2CMasterWires wires=i2cm.wires;
    method Bit#(7) last_responsed if(!i2cm.ops.is_busy);
        return _last_responsed;
    endmethod
endmodule

interface LM75Reader;
    interface I2CMasterWires wires;
    method Bit#(16) value;
    (*always_enabled,always_ready*)
    method Action slave_addr(Bit#(7) a);
endinterface


(*synthesize*)
module mkLM75Reader(LM75Reader);
    I2CMaster i2cm<-mkI2CMaster(7);
    Reg#(Bit#(16)) _value<-mkReg('haa);
    Reg#(Bit#(7)) addr<-mkReg(0);
    //Reg#(Bit#(8)) current_addr<-mkReg(0);
    mkAutoFSM(
        seq
            while(True)seq
                i2cm.ops.request.put(tagged Start);
                i2cm.ops.request.put(tagged Write ({addr,0}));
                i2cm.ops.request.put(tagged GetAck);

                
                i2cm.ops.request.put(tagged Write 8'h00);
                i2cm.ops.request.put(tagged GetAck);

                i2cm.ops.request.put(tagged Start);
                i2cm.ops.request.put(tagged Write ({addr,1}));
                i2cm.ops.request.put(tagged GetAck);
                
                //i2cm.ops.request.put(Stop, 0);
                i2cm.ops.request.put(tagged Read);
                i2cm.ops.request.put(tagged PutAck);
                action 
                    let x1<- i2cm.ops.response.get();
                    case (x1) matches
                        tagged Received .x :_value[15:8]<=x;
                    endcase
                endaction
                i2cm.ops.request.put(tagged Read);
                i2cm.ops.request.put(tagged PutAck);
                action 
                    let x2<-i2cm.ops.response.get();
                    _value[7:0]<=x2.Received;
                endaction
                i2cm.ops.request.put(tagged Stop);
            endseq
        endseq
    );


    interface I2CMasterWires wires=i2cm.wires;
    method Bit#(16) value() if(!i2cm.ops.is_busy);
        return _value;
    endmethod

    method Action slave_addr(Bit#(7) a);
        addr<=a;
    endmethod
endmodule
