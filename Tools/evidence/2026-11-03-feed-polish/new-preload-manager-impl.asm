0x80a0e4c: stp      x24, x23, [sp, #-0x40]!                  
0x80a0e50: stp      x22, x21, [sp, #0x10]                    
0x80a0e54: stp      x20, x19, [sp, #0x20]                    
0x80a0e58: stp      x29, x30, [sp, #0x30]                    
0x80a0e5c: add      x29, sp, #0x30                           
0x80a0e60: adrp     x8, #0x239cc000                          
0x80a0e64: ldr      x23, [x8, #0xbd0]                        
0x80a0e68: ldr      x19, [x20, x23]                          
0x80a0e6c: mov      x21, x19                                 
0x80a0e70: cmp      x19, #1                                  
0x80a0e74: b.ne     #0x80a0f2c                               
0x80a0e78: adrp     x0, #0x23675000                          
0x80a0e7c: add      x0, x0, #0x248                           
0x80a0e80: bl       #0xf8892b4                               
0x80a0e84: mov      x1, x0                                   
0x80a0e88: bl       #0xf889930                               
0x80a0e8c: mov      x21, x0                                  
0x80a0e90: cbz      x0, #0x80a0f14                           
0x80a0e94: adrp     x8, #0x2257b000                          
0x80a0e98: ldr      x1, [x8, #0x560]                          ; __objc_selrefs awemePreloaderClass
0x80a0e9c: mov      x0, x21                                  
0x80a0ea0: bl       #0xf887f9c                               
0x80a0ea4: mov      x22, x0                                  
0x80a0ea8: mov      x0, x21                                  
0x80a0eac: bl       #0xf8892e0                               
0x80a0eb0: cbz      x22, #0x80a0f10                          
0x80a0eb4: mov      x0, x22                                  
0x80a0eb8: bl       #0xf889370                               
0x80a0ebc: bl       #0xf889a60                               
0x80a0ec0: mov      x21, x0                                  
0x80a0ec4: adrp     x8, #0x1a475000                          
0x80a0ec8: add      x8, x8, #0xfa0                            ; 0x1a475fa0 paid_series_detail_page; 0x1a475fc0 share_panel_config
0x80a0ecc: sub      x8, x8, #0x20                            
0x80a0ed0: orr      x1, x8, #0x8000000000000000              
0x80a0ed4: mov      x0, #0x17                                
0x80a0ed8: movk     x0, #0xd000, lsl #48                     
0x80a0edc: bl       #0xf889340                               
0x80a0ee0: mov      x22, x0                                  
0x80a0ee4: adrp     x8, #0x2271e000                          
0x80a0ee8: ldr      x1, [x8, #0x240]                          ; __objc_selrefs preloaderWithBizScene:
0x80a0eec: mov      x0, x21                                  
0x80a0ef0: mov      x2, x22                                  
0x80a0ef4: bl       #0xf887f9c                               
0x80a0ef8: mov      x29, x29                                 
0x80a0efc: bl       #0xf887fa8                               
0x80a0f00: mov      x21, x0                                  
0x80a0f04: mov      x0, x22                                  
0x80a0f08: bl       #0xf887f84                               
0x80a0f0c: b        #0x80a0f14                               
0x80a0f10: mov      x21, #0                                  
0x80a0f14: ldr      x22, [x20, x23]                          
0x80a0f18: str      x21, [x20, x23]                          
0x80a0f1c: mov      x0, x21                                  
0x80a0f20: bl       #0xf88930c                               
0x80a0f24: mov      x0, x22                                  
0x80a0f28: bl       #0xf8a49b8                               
0x80a0f2c: mov      x0, x19                                  
0x80a0f30: bl       #0xf8a49b4                               
0x80a0f34: mov      x0, x21                                  
0x80a0f38: ldp      x29, x30, [sp, #0x30]                    
0x80a0f3c: ldp      x20, x19, [sp, #0x20]                    
0x80a0f40: ldp      x22, x21, [sp, #0x10]                    
0x80a0f44: ldp      x24, x23, [sp], #0x40                    
0x80a0f48: ret                                               
0x80a0f4c: sub      sp, sp, #0x50                            
0x80a0f50: stp      x24, x23, [sp, #0x10]                    
0x80a0f54: stp      x22, x21, [sp, #0x20]                    
0x80a0f58: stp      x20, x19, [sp, #0x30]                    
0x80a0f5c: stp      x29, x30, [sp, #0x40]                    
0x80a0f60: add      x29, sp, #0x40                           
0x80a0f64: mov      x21, x20                                 
0x80a0f68: mov      x22, x2                                  
0x80a0f6c: mov      x23, x1                                  
0x80a0f70: mov      x19, x0                                  
0x80a0f74: bl       #0xf8e4090                               
0x80a0f78: tbz      w0, #0, #0x80a0f80                       
0x80a0f7c: cbnz     x19, #0x80a0f98                          
0x80a0f80: ldp      x29, x30, [sp, #0x40]                    
0x80a0f84: ldp      x20, x19, [sp, #0x30]                    
0x80a0f88: ldp      x22, x21, [sp, #0x20]                    
0x80a0f8c: ldp      x24, x23, [sp, #0x10]                    
0x80a0f90: add      sp, sp, #0x50                            
0x80a0f94: ret                                               
0x80a0f98: mov      x0, x19                                  
0x80a0f9c: bl       #0xf887fb0                               
0x80a0fa0: mov      x20, x21                                 
0x80a0fa4: bl       #0x80a11b4                               
0x80a0fa8: cbz      x0, #0x80a0fdc                           
0x80a0fac: mov      x20, x0                                  
0x80a0fb0: mov      x0, x19                                  
0x80a0fb4: bl       #0xf887fb0                               
0x80a0fb8: adrp     x8, #0x2271d000                          
0x80a0fbc: ldr      x1, [x8, #0xea0]                          ; __objc_selrefs preloadVideoWithModel:
0x80a0fc0: mov      x0, x20                                  
0x80a0fc4: mov      x2, x19                                  
0x80a0fc8: bl       #0xf887f9c                               
0x80a0fcc: mov      x0, x19                                  
0x80a0fd0: bl       #0xf887f84                               
0x80a0fd4: mov      x0, x20                                  
0x80a0fd8: bl       #0xf8892e0                               
0x80a0fdc: mov      x8, #-0x2000000000000000                 
0x80a0fe0: stp      xzr, x8, [sp]                            
0x80a0fe4: mov      x20, sp                                  
0x80a0fe8: mov      w0, #0x25                                
0x80a0fec: bl       #0xf8892fc                               
0x80a0ff0: ldr      x0, [sp, #8]                             
0x80a0ff4: bl       #0xf8892f4                               
0x80a0ff8: adrp     x8, #0x1aa60000                          
0x80a0ffc: add      x8, x8, #0x7c0                            ; 0x1aa607c0 preload video: trigger:; 0x1aa607e0 [pineDramaInnerFeedPreload]
0x80a1000: sub      x8, x8, #0x20                            
0x80a1004: orr      x8, x8, #0x8000000000000000              
0x80a1008: mov      x9, #0x17                                
0x80a100c: movk     x9, #0xd000, lsl #48                     
0x80a1010: stp      x9, x8, [sp]                             
0x80a1014: mov      x20, sp                                  
0x80a1018: mov      x0, x23                                  
0x80a101c: mov      x1, x22                                  
0x80a1020: bl       #0xf8892f8                               
0x80a1024: mov      x0, #0x202c                              
0x80a1028: movk     x0, #0x7761, lsl #16                      ; small ', aw'
0x80a102c: movk     x0, #0x6d65, lsl #32                      ; small ', awem'
0x80a1030: movk     x0, #0x4965, lsl #48                      ; small ', awemeI'
0x80a1034: mov      x20, sp                                  
0x80a1038: mov      x1, #0x3a64                              
0x80a103c: movk     x1, #0xea00, lsl #48                     
0x80a1040: bl       #0xf8892f8                               
0x80a1044: mov      x0, x19                                  
0x80a1048: bl       #0xf8c4f4c                               
0x80a104c: cmp      x1, #0                                   
0x80a1050: mov      w8, #0x756e                              
0x80a1054: movk     w8, #0x6c6c, lsl #16                     
0x80a1058: csel     x0, x8, x0, eq                           
0x80a105c: mov      x8, #-0x1c00000000000000                 
0x80a1060: csel     x22, x8, x1, eq                          
0x80a1064: mov      x20, sp                                  
0x80a1068: mov      x1, x22                                  
0x80a106c: bl       #0xf8892f8                               
0x80a1070: mov      x0, x22                                  
0x80a1074: bl       #0xf8892f4                               
0x80a1078: ldp      x0, x22, [sp]                            
0x80a107c: mov      x1, x22                                  
0x80a1080: mov      x20, x21                                 
0x80a1084: bl       #0x80a11c0                               
0x80a1088: mov      x0, x19                                  
0x80a108c: bl       #0xf887f84                               
0x80a1090: mov      x0, x22                                  
0x80a1094: ldp      x29, x30, [sp, #0x40]                    
0x80a1098: ldp      x20, x19, [sp, #0x30]                    
0x80a109c: ldp      x22, x21, [sp, #0x20]                    
0x80a10a0: ldp      x24, x23, [sp, #0x10]                    
0x80a10a4: add      sp, sp, #0x50                            
0x80a10a8: b        #0xf8892f4                               
0x80a10ac: sub      sp, sp, #0x50                            
0x80a10b0: stp      x22, x21, [sp, #0x20]                    
0x80a10b4: stp      x20, x19, [sp, #0x30]                    
0x80a10b8: stp      x29, x30, [sp, #0x40]                    
0x80a10bc: add      x29, sp, #0x40                           
0x80a10c0: mov      x19, x1                                  
0x80a10c4: mov      x21, x0                                  
0x80a10c8: mov      x8, #-0x2000000000000000                 
0x80a10cc: stp      xzr, x8, [sp, #0x10]                     
0x80a10d0: add      x20, sp, #0x10                           
0x80a10d4: mov      w0, #0x1d                                
0x80a10d8: bl       #0xf8892fc                               
0x80a10dc: ldr      x0, [sp, #0x18]                          
0x80a10e0: bl       #0xf8892f4                               
0x80a10e4: adrp     x8, #0x1aa60000                          
0x80a10e8: add      x8, x8, #0x7e0                            ; 0x1aa607e0 [pineDramaInnerFeedPreload]; 0x1aa60800 TikTokPineDramaImpl/PineDramaInnerFeedVideoPreloadManager.swift
0x80a10ec: sub      x8, x8, #0x20                            
0x80a10f0: orr      x8, x8, #0x8000000000000000              
0x80a10f4: mov      x9, #0x1b                                
0x80a10f8: movk     x9, #0xd000, lsl #48                     
0x80a10fc: stp      x9, x8, [sp, #0x10]                      
0x80a1100: add      x20, sp, #0x10                           
0x80a1104: mov      x0, x21                                  
0x80a1108: mov      x1, x19                                  
0x80a110c: bl       #0xf8892f8                               
0x80a1110: ldp      x1, x19, [sp, #0x10]                     
0x80a1114: mov      w8, #2                                   
0x80a1118: strb     w8, [sp, #8]                             
0x80a111c: mov      w8, #7                                   
0x80a1120: str      x8, [sp]                                 
0x80a1124: adrp     x3, #0x1aa60000                          
0x80a1128: add      x3, x3, #0x800                            ; 0x1aa60800 TikTokPineDramaImpl/PineDramaInnerFeedVideoPreloadManager.swift
