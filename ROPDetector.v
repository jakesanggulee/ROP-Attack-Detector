
module ROPDetector (

	input iClk,
	input iRsn,
	input [31:0] iTRAMPOLINE_START,
	input [31:0] iTRAMPOLINE_END,
	input iFifo_Empty,
	input [31:0] iFifo_Data,
	output reg oFifo_RdEn,
	output reg oRopDetect

);


/* Local Parameters */
parameter H = 1'b1, L = 1'b0;
parameter MAX_STACK 					=	20;
parameter STACK_EMPTY_SP				=	0;
parameter TRAMPOLINE_FUNCTION_GAP			=	8;
parameter TRAMPOLINE_FUNCTION_CALL_RETURN_DISTANCE	=	4;
parameter MAX_STACKPOINTER_BIT				=	5;
parameter MAX_SIGNED_BIT				=	7;
integer i;

/* Local Variables */
reg signed [MAX_SIGNED_BIT-1:0]	shadow_stack [MAX_STACK-1:0];	//shadow stack decl
reg signed [MAX_SIGNED_BIT-1:0] last_call;			//Stores the latest Call
reg signed [MAX_SIGNED_BIT-1:0] command;			//decoded command
reg [MAX_STACKPOINTER_BIT-1:0]	shadow_stack_sp;		//shadow stack stackpointer
reg				decodeEn;			//should decode next byte


/* Fetch Data From FIFO and Decode Packet */
always @* begin

	/* command > 0 : Function Call ( e.g  3 = Call 3 , 2 = Call 2 )	
	command < 0 : Function Return ( e.g -3 =Return 3, -2 = Return 2 )
	command = 0 : Direct Jump (0 = Direct Jump ) 	*/	

	command <= decode(iFifo_Data, iTRAMPOLINE_START, iTRAMPOLINE_END );


end


/* Stores the Latest Call */
always @* begin
	
	if ( shadow_stack_sp > 0 ) 
		last_call <= shadow_stack[ shadow_stack_sp - 1 ];
	else
		last_call <= 0;


end



always @ ( posedge iClk or negedge iRsn ) begin

	/* Reset Logic */
	if(!iRsn) begin 
		
		for ( i = 0 ; MAX_STACK > i ; i = i+1 ) begin
			shadow_stack[i] <= 0;
		end

		oFifo_RdEn <= L;
		oRopDetect <= L;
		shadow_stack_sp <= STACK_EMPTY_SP;
		decodeEn <= L;

	end 

	/* Normal Operation */
	else begin

		/* Fifo Control */
		if ( iFifo_Empty ) begin
			oFifo_RdEn <= L;
		end else begin
			oFifo_RdEn <= H;
		end
		

		/* Should Read Next-byte */
		if ( oFifo_RdEn ) begin
			decodeEn <= H;
		end else begin
			decodeEn <= L;
		end


		/* Decode & ROP Detect Logic */
		if ( decodeEn ) begin	

			if ( command > 0 ) begin // function call -> Push to Stack
			
				shadow_stack_sp 		<= shadow_stack_sp + 1;
				shadow_stack[shadow_stack_sp] 	<= command;
				oRopDetect 			<= L;

			end else if ( command < 0 ) begin // function Return -> Pop from Stack 
				
				shadow_stack_sp <= shadow_stack_sp - 1;

				//Check for ROP
				if( last_call != command * -1 ) begin

					oRopDetect 		<= H;

				end else begin

					oRopDetect 		<= L;

				end
			end else begin		// direct Jump -> drop packet

					oRopDetect 		<= L;
			end

		end else begin

			oRopDetect <= L;

		end
	end 

end // end always



/* Fetch Data From FIFO and Decode Packet */
function integer decode;	//Combinational Logic

input [31:0] fifo_data;
input [31:0] t_start;
input [31:0] t_end;

integer quotient, remainder;

begin

	if ( fifo_data >= t_start && fifo_data <= t_end ) begin

		quotient  =  (fifo_data - t_start) / TRAMPOLINE_FUNCTION_GAP;
		remainder =  (fifo_data - t_start) % TRAMPOLINE_FUNCTION_GAP;

		if( remainder  == 0 ) begin
			decode = quotient + 1;	//function call
		end else begin
			decode = -1*(quotient + 1); 	//function return
		end

	end else begin
		decode = 0;	//direct jump
	end
end

endfunction


endmodule




