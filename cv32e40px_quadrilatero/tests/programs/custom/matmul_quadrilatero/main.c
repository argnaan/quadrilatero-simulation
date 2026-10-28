#include <stdint.h>
#include <stdio.h>
#include "matrixData.h"
#include "matmul.h"

#define WAIT_COMPLETE 10

C_DTYPE __attribute__((section(".data"), aligned(4))) matC[DIM_M*DIM_N] = {};

#define PRINTF(fmt, ...)    printf(fmt, ## __VA_ARGS__)
//#define PRINTF(fmt, ...)    

#if DTC == 0 | DTC == 1 | DTC == 2 | DTC == 8 | DTC == 9 | DTC == 10
    #define CHECK_CONDITION int_condition
#else 
    #define CHECK_CONDITION float_condition
#endif

uint32_t check_results();

int main() {
    PRINTF("\nEntering main\n\r");

    uint32_t errors = 0;
    unsigned int cycles;
    
    unsigned int zero = 0; 
    unsigned int enable = 0xfffffff8; /* cycles and instr count enable */
    __asm__ volatile("csrw 0xb00, %0" ::"r"(zero));
    __asm__ volatile("csrw 0xb02, %0" ::"r"(zero));
    __asm__ volatile("csrw 0x320, %0" ::"r"(enable));

    matmul_custom(matAT, matB, matC, DIM_K, DIM_N, DIM_M, WIDENING);

    for(volatile int i=0; i<WAIT_COMPLETE; i++);

    errors = check_results();

    __asm__ volatile("csrr %0, 0xb00" : "=r"(cycles));

    PRINTF("Program finished with %d errors and %d cycles\n\r", errors, cycles);

    return errors;
}

int float_condition(int index){
    C_DTYPE diff;

    diff = matC[index] - matC_gold[index];
    if (diff < 0) diff = -diff; 
    return (diff > 0.001f);
}

int int_condition(int index){
    return (matC[index] != matC_gold[index]);
}

uint32_t check_results()
{
    int i, j;
    uint32_t err = 0;

    for(i = 0; i < DIM_M; i++) {
        for(j = 0; j < DIM_N; j++) {
           if(CHECK_CONDITION(i*DIM_N+j)) {
                err ++;
                PRINTF("Error at index %d, %d, expected %d, got %d\n\r", i, j, matC_gold[i*DIM_N+j], matC[i*DIM_N+j]);
            }
        }
    }
    return err;
}