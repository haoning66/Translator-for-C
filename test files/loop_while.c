#include <stdio.h>

// This test should be okay, since while statements are defined.

int main() 
{
  int i;
  i = 0;
  while (i < 10){
    printf("hello\n");
    i = i + 1;
  }
  return 0;
}
