`timescale	1ns/1ns

/*
Decoding Table

where 

*	cnt indicates previous address byte size
*	excp indicates whether the next byte is exception byte

cnt == 0 && iBytePacket == 0XXX XXX1 then  oAddressEn = H, oAddress[7:2] = iBytePacket[6:1] has_excp = 0;
cnt == 0 && iBytePacket == 1XXX XXX1 then  oAddressEn = L, oAddress[7:2] = iBytePacket[6:1] , cnt = 1 has_excp =0;

cnt == 1 && iBytePacket == 00XX XXXX then oAddressEn = H, oAddress[14:8] = iBytePacket[6:0] has_excp = 0;
cnt == 1 && iBytePacket == 01XX XXXX then oAddressEn = L, oAddress[14:8] = iBytePacket[6:0], has_excp = 1;
cnt == 1 && iBytePacket == 1XXX XXXX then oAddressEn = L, oAddress[14:8] = iBytePacket[6:0], cnt == 010 excp = 0;

cnt == 2 && iBytePacket == 00XX XXXX then oAddressEn = H, oAddress[21:15] = iBytePacket[6:0] has_excp = 0;
cnt == 2 && iBytePacket == 01XX XXXX then oAddressEn = L, oAddress[21:15] = iBytePacket[6:0], has_excp = 1;
cnt == 2 && iBytePacket == 1XXX XXXX then oAddressEn = L, oAddress[21:15] = iBytePacket[6:0], cnt == 011 excp = 0;

cnt == 3 && iBytePacket == 00XX XXXX then oAddressEn = H, oAddress[28:22] = iBytePacket[6:0] has_excp = 0;
cnt == 3 && iBytePacket == 01XX XXXX then oAddressEn = L, oAddress[28:22] = iBytePacket[6:0], has_excp = 1;
cnt == 3 && iBytePacket == 1XXX XXXX then oAddressEn = L, oAddress[28:22] = iBytePacket[6:0], cnt == 100 excp = 0;

cnt == 4 && iBytePacket == 0000 1XXX then oAddressEn = H, oAddress[31:29] = iBytePacket[2:0] has_excp = 0;
cnt == 4 && iBytePacket == 0100 1XXX then oAddressEn = H, oAddress[31:29] = iBytePacket[2:0] has_excp = 1;

excp == 1 and iBytePacket == 000XXXXX then Exception[3:0] = iBytePacket[4:1],  oAddressEn = H, 


*/


module decoder(
		input iClk,
		input iRsn,
		input iBytePacketEn,
		input [7:0] iBytePacket,
		output reg oAddressEn,
		output reg [31:0] oAddress
);

//parameters
parameter H = 1'b1, L = 1'b0;

parameter ARM = 2;
parameter THUMB = 1;

parameter RD_Header    = 0;
parameter RD_Byte_1    = 1;
parameter RD_Byte_2    = 2;
parameter RD_Byte_3    = 3;
parameter RD_Byte_4    = 4;
parameter RD_Exception = 5;
parameter RD_Hyp       = 6;

// Declare Registers
reg [8:0] Exception;
reg NS, Hyp;
reg [2:0] cnt; // conut received Address Bytes


always @ ( posedge iClk ) begin
	
	if( iBytePacketEn ) begin

		case ( cnt ) 

			RD_Header : begin		//Read Header  Byte Signiture	XXXX XXX1
			
				if( iBytePacket[0] ) begin
					NS <= L;
					Hyp <= L;
					oAddress <= {32{L}} | (iBytePacket[6:1] << ARM);
					
					if( iBytePacket[7] ) begin
						cnt <= RD_Byte_1;
						oAddressEn <= L;

					end else begin
						oAddressEn <= H;
					end

				end

			end

			RD_Byte_1, RD_Byte_2, RD_Byte_3 : begin

				oAddress <= oAddress | iBytePacket[6:0] << ( 7*(cnt-1) + ARM + 6 );
				
				if( iBytePacket[7] ) begin	//Read Next Byte if 'C' Signiture is H
					cnt <= cnt + 1;
				end else begin
					
					if( iBytePacket[6] ) begin
						cnt <= RD_Exception;
					end else begin
						cnt <= RD_Header;
						oAddressEn <= H;
					end


				end

			end

			RD_Byte_4 : begin		//Read Last Byte
				oAddress <= oAddress | iBytePacket[2:0] << ( 27 + ARM  );
					
					if( iBytePacket[6] ) begin
						cnt <= RD_Exception;
					end else begin
						cnt <= RD_Header;
						oAddressEn <= H;
					end
			end

			RD_Exception : begin		//Read Exception Byte

					NS <= iBytePacket[0];
					Exception[3:0] <= iBytePacket[4:1];

					if ( iBytePacket[7] ) begin
						cnt <= RD_Hyp;
					end else begin
						oAddressEn <= H;
						cnt <= RD_Header;
					end					

			end 

			RD_Hyp : begin			//Read Hyp	Byte

					Exception[8:4] <= iBytePacket[4:0];
					Hyp <= iBytePacket[5];
					cnt <= RD_Header;
					oAddressEn <= H;

			end

		endcase

	end else begin

				if( oAddressEn ) begin
					oAddressEn <= L;
				end

	end

end



// Reset Function
always @ ( posedge iClk or negedge iRsn ) begin

	if(!iRsn) begin
		NS <= L;
		Hyp <= L;
		cnt <= {3{L}};
		oAddress <= {32{L}};
		oAddressEn <= L;
	end



end

endmodule



