/* Created By Sang Gu Lee... Jul 17th */

`timescale 1ns/10ps

module test;

/* Input & Output */
bit iClk; 
bit iRsn;
bit [31:0] iTRAMPOLINE_START;
bit [31:0] iTRAMPOLINE_END;
bit [31:0] iFifo_Data;
bit iFifo_Empty;
wire oFifo_RdEn, oRopDetect;
bit prev_oFifo_RdEn;

/* Testbench Control Parameters */
localparam CLK_HALF_CYCLE 	= 5; 			//clock half cycle 
localparam TEST_NUM 		= 100;			//number of generated tests
localparam MIN_TRAMPOLINE_ADDR	= 32'h80000000;

//localparam MAX_TRAMPOLINE_ADDR	= 32'hFFFFFFFF;
localparam MAX_TRAMPOLINE_ADDR	= 32'h80000080; 	// Fix Min_trampoline_addr to 32'h80000000
localparam MAX_FUNCTION_CALLS 	= 5;			//maximum number of generated func
localparam MAX_FUNCTION_INDEX 	= 5;  			//maximum index of generated func
localparam MAX_DIRECT_JUMP_EACH	= 2; 			//#of d-jump between two function calls/returns
localparam MAX_PACKET_LEN	= (MAX_FUNCTION_CALLS*2)*( 1 + MAX_DIRECT_JUMP_EACH )+2;
localparam MAX_STACK_LENGTH	=30;



/* Stack */
struct {

	int sp;
	int data [MAX_STACK_LENGTH];

} stk;

/* Test Info Struct */
struct {

	int seq[MAX_PACKET_LEN];
	int seq_length;
	int rop_pos;
	bit [31:0] addr[MAX_PACKET_LEN];
	bit [31:0] tramp[2]; 
	bit is_rop;

} t[TEST_NUM];


/* Current Test Info */
struct {
	int cur_test;
	int cur_idx;
} ti;


/* ROP prediction Result */
struct {
	//int pred;
	int cur_idx;
} pi[TEST_NUM];



/* Module Instance */
ROPDetector D1(.*);



/* Simulation Logic */
initial begin

	reset();

	//Generate Required Address
	mk_addr();	

	#10;

	for(int tp = 0; TEST_NUM > tp ; tp++) begin
	
		print_info(tp);		//print current test info
		drive(tp);		//drive signal


	end

	print_result();

	$finish();

end



/* Clock Generator */
always #CLK_HALF_CYCLE iClk = ~iClk;



/* Generating Random Fifo Status - FIFO empty => 0.25 Probability */
always @(posedge iClk) begin		 

	if(!iRsn) begin
		iFifo_Empty <= 1'b1;	
	end else if( random_bit() && random_bit() ) begin
			iFifo_Empty <= 1'b1;
	end else begin
			iFifo_Empty <= 1'b0;	
	end

	prev_oFifo_RdEn <=  oFifo_RdEn;

end



/* Check oRopDetect Signal */
always @(posedge oRopDetect ) begin

	if( prev_oFifo_RdEn ==1'b0 ) begin
		$display("\nDetected ROP attack %d %d",ti.cur_test, ti.cur_idx );		
		pi[ti.cur_test].cur_idx = ti.cur_idx;
	end else begin
		$display("\nDetected ROP attack %d %d",ti.cur_test, ti.cur_idx -1 );
		pi[ti.cur_test].cur_idx = ti.cur_idx-1;

	end
end




/* Reset Task */
task reset;

	iRsn = 0;
	#60ns;
	iRsn = 1;
	stack_init();

endtask



/* Signal Driver Task */
task drive (int tp);

	int i;
	i = 0;

	while ( t[tp].seq_length > i ) begin
		
		@ (posedge iClk);	
	
		//Send Packet only when RdEn is H
		if( oFifo_RdEn ) begin 	

			ti.cur_test 		<= tp;
			ti.cur_idx 		<= i; 
			iTRAMPOLINE_START 	<= t[tp].tramp[0];
			iTRAMPOLINE_END 	<= t[tp].tramp[1];
			iFifo_Data		<= t[tp].addr[i];
			i++;
			
		end
		
	end	

endtask



function void print_result();

	int suc,tot;
	suc = 0;
	tot = 0;
	$display("\n");

	for( int i = 0; TEST_NUM > i; i ++ ) begin

		if( t[i].is_rop ) begin
			tot++;
			if( t[i].rop_pos == pi[i].cur_idx ) begin
				suc++;
				$display("Correct ! %2dth Pacekt , Index %2d", i , pi[i].cur_idx );
			end else begin
				$display("ERROR   ! (Real : %2dth Pacekt , Index %2d ) But received ( %2dth Pacekt , Index %2d )", i, t[i].rop_pos, i, pi[i].cur_idx );
			end

		end

	end

	$display("\n[ Final Result  Correct: %2d / %2d  ]>>>>>>>>>>",suc,tot );

endfunction



/* Print Function Call & Return Information */
function void print_info(int tp);


	// Clean Packet OR ROP Injected Packet
	if ( t[tp].is_rop == 0)
		$display("\n[%2dth Test] \nTrampoline start: 0x%x  Trampoline end: 0x%x] \n>>Packet Status: [Clean Packet]\n", tp ,t[tp].tramp[0],t[tp].tramp[1]);
	else
		$display("\n[%2dth Test] \nTrampoline start: 0x%x  Trampoline end: 0x%x] \n>>Packet Status: [ROP Injected Packet]\n", tp ,t[tp].tramp[0],t[tp].tramp[1]);


	for (int  i = 0 ; t[tp].seq_length > i ; i++) begin
		
		if( t[tp].is_rop && (t[tp].rop_pos == i) ) begin
	
			$write( "[ 0x%10x : ROP    ] <<<<<<<< ROP ATTACK [ This Value should be #RET %1d #  ]\n", t[tp].addr[i],-1* (t[tp].seq[i]));

		end else begin
	
			if( t[tp].seq[i] > 0 )
				$write( "[ 0x%10x : CALL %1d ] \n", t[tp].addr[i], t[tp].seq[i] );
			else if( t[tp].seq[i] < 0 )
				$write( "[ 0x%10x : RET  %1d ] \n", t[tp].addr[i],-1* t[tp].seq[i] );
			else
				$write( "[ 0x%10x : DJMP   ] \n",t[tp].addr[i] );
		end
	end

endfunction




/* Generates Test Addresses */
function void mk_addr(); 


	//Random ROP Packets
	static bit [TEST_NUM-1:0] random_vector;// = $urandom();
	randomize(random_vector);


	//Make Valid Address
	for (int i = 0 ; TEST_NUM > i ; i++ ) begin

		//Generate Valid Sequence
		mk_seq(i);
	
		t[i].tramp[0] =  $urandom_range (MIN_TRAMPOLINE_ADDR, MAX_TRAMPOLINE_ADDR );
		t[i].tramp[1] =  t[i].tramp[0] + 32'h8 * (MAX_FUNCTION_CALLS -1 ) + 32'h4;
	
			for (int j = 0 ; t[i].seq_length > j; j++) begin
		
				//function call
				if( t[i].seq[j] > 0 ) begin
	
					t[i].addr[j] =t[i].tramp[0] + 32'h8 * ( t[i].seq[j] - 1 ); 
	
				//function ret
				end else if ( t[i].seq[j] < 0 ) begin
				
					t[i].addr[j] = t[i].tramp[0] + 32'h8 * ( -1* (t[i].seq[j]) - 1 )+ 32'h4; 
	
				//direct jump
				end else begin
	
					t[i].addr[j] =  $urandom_range ( 0, MIN_TRAMPOLINE_ADDR -1 );
		
				end
	
			end
	end


	for(int i = 0; TEST_NUM > i ; i++) begin
	
		if ( random_vector[i] == 1 )
			t[i].is_rop = 1;
		else
			t[i].is_rop = 0;

	end


	//Injecting ROP Packet
	for(int i = 0; TEST_NUM > i ; i++) begin
		if ( t[i].is_rop == 1 )
			inject_rop(i);
	end

endfunction



/* ROP Attack Injection  -> Alter Normal address */
function void inject_rop(int i);

int new_val;

	for( int j =0; t[i].seq_length > j ; j ++ ) begin
		if( t[i].seq[j] < 0 ) begin

			new_val = t[i].tramp[0] + 4  + 8 * $urandom_range(0, ( t[i].tramp[1] - t[i].tramp[0] - 4) % 8 + 2);

			if( t[i].addr[j] != new_val ) begin
				t[i].addr[j] = new_val;
			end else begin

				if( t[i].addr[j] != t[i].tramp[0] + 4 )
					t[i].addr[j] = t[i].tramp[0] + 4;
				else
					t[i].addr[j] = t[i].tramp[0] + 12;
			

			end
			t[i].rop_pos = j;
			break;
		end
	end

endfunction



/* Generate Valid Sequence */
function void mk_seq (int i);

bit action; 		
int call_idx, nc, pos, ncalls;
int j;

	nc = 0;
	pos = 0;
	ncalls = $urandom_range(2,MAX_FUNCTION_CALLS);

	while ( ncalls > nc ) begin

		action = !stack_is_empty() && random_bit();

		if( action ) begin

			t[i].seq[pos++] = -1 * stack_pop();

		end else begin

			call_idx = $urandom_range(1,MAX_FUNCTION_INDEX); 
			t[i].seq[pos++] = call_idx;
			stack_push(call_idx);
			nc ++;
		end


		//write direct jump
		for ( j = $urandom_range(0,MAX_DIRECT_JUMP_EACH) ; j > 0 ; j--) begin
			t[i].seq[pos++] = 0;
		end		
		
	end
	

	//write remaining returns
	while( !stack_is_empty() ) begin
		t[i].seq[pos++] = -1 * stack_pop();
	end

	t[i].seq_length = pos;

endfunction




/*	Stack functions...	*/

function void stack_push(input int data) ;
	stk.data[++stk.sp] = data;
endfunction

function int stack_pop();
	if(stk.sp > -1 ) return stk.data[stk.sp--];
endfunction

function void stack_init() ;
	stk.sp = -1;
endfunction

function int stack_is_empty();
	if(stk.sp > -1)
		return 0;
	else
		return 1;
endfunction



function bit random_bit();
	return $urandom_range(0,1);
endfunction


endmodule

