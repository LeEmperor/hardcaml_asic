// PDK-free structural fixtures for the reviewed supplied functional forms.
// Native supplied-source qualification is separate; these are not PDK evidence.
module sg13cmos5l_buf_1 (X, A);
 output X; input A;
 buf (X, A);
 specify (A => X) = (0.0,0.0); endspecify
endmodule
module sg13cmos5l_dfrbpq_1 (Q, CLK, D, RESET_B);
 output Q; input CLK, D, RESET_B;
 reg notifier;
 wire delayed_D, delayed_RESET_B, delayed_CLK;
 wire int_fwire_IQ, int_fwire_r, xcr_0;
 not (int_fwire_r, delayed_RESET_B);
 buf (xcr_0, 0);
 ihp_dff_r (int_fwire_IQ, notifier, delayed_CLK, delayed_D, int_fwire_r, xcr_0);
 buf (Q, int_fwire_IQ);
 specify
   $setuphold (posedge CLK, posedge D, 0.0, 0.0, notifier,,, delayed_CLK, delayed_D);
   $recrem (posedge RESET_B, posedge CLK, 0.0, 0.0, notifier,,, delayed_RESET_B, delayed_CLK);
 endspecify
endmodule
module sg13cmos5l_dfrbpq_2 (Q, CLK, D, RESET_B);
 output Q; input CLK, D, RESET_B;
 reg notifier;
 wire delayed_D, delayed_RESET_B, delayed_CLK;
 wire int_fwire_IQ, int_fwire_r, xcr_0;
 not (int_fwire_r, delayed_RESET_B);
 buf (xcr_0, 0);
 ihp_dff_r (int_fwire_IQ, notifier, delayed_CLK, delayed_D, int_fwire_r, xcr_0);
 buf (Q, int_fwire_IQ);
 specify
   $setuphold (posedge CLK, posedge D, 0.0, 0.0, notifier,,, delayed_CLK, delayed_D);
   $recrem (posedge RESET_B, posedge CLK, 0.0, 0.0, notifier,,, delayed_RESET_B, delayed_CLK);
 endspecify
endmodule
module sg13cmos5l_dfrbp_1 (Q, Q_N, CLK, D, RESET_B);
 output Q, Q_N; input CLK, D, RESET_B;
 reg notifier;
 wire delayed_D, delayed_RESET_B, delayed_CLK;
 wire int_fwire_IQ, int_fwire_IQN, int_fwire_r;
 wire xcr_0;
 not (int_fwire_r, delayed_RESET_B);
 buf (xcr_0, 0);
 ihp_dff_r (int_fwire_IQ, notifier, delayed_CLK, delayed_D, int_fwire_r, xcr_0);
 buf (Q, int_fwire_IQ);
 not (int_fwire_IQN, int_fwire_IQ);
 buf (Q_N, int_fwire_IQN);
 specify
   $setuphold (posedge CLK, posedge D, 0.0, 0.0, notifier,,, delayed_CLK, delayed_D);
   $recrem (posedge RESET_B, posedge CLK, 0.0, 0.0, notifier,,, delayed_RESET_B, delayed_CLK);
 endspecify
endmodule
module sg13cmos5l_dfrbp_2 (Q, Q_N, CLK, D, RESET_B);
 output Q, Q_N; input CLK, D, RESET_B;
 reg notifier;
 wire delayed_D, delayed_RESET_B, delayed_CLK;
 wire int_fwire_IQ, int_fwire_IQN, int_fwire_r;
 wire xcr_0;
 not (int_fwire_r, delayed_RESET_B);
 buf (xcr_0, 0);
 ihp_dff_r (int_fwire_IQ, notifier, delayed_CLK, delayed_D, int_fwire_r, xcr_0);
 buf (Q, int_fwire_IQ);
 not (int_fwire_IQN, int_fwire_IQ);
 buf (Q_N, int_fwire_IQN);
 specify
   $setuphold (posedge CLK, posedge D, 0.0, 0.0, notifier,,, delayed_CLK, delayed_D);
   $recrem (posedge RESET_B, posedge CLK, 0.0, 0.0, notifier,,, delayed_RESET_B, delayed_CLK);
 endspecify
endmodule
module sg13cmos5l_unreviewed_1 (Q, D);
 output Q; input D; wire delayed_D;
 assign Q=delayed_D;
endmodule
