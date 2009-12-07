
#include <iostream>
using namespace std;

#include "everything.h"

int main() {
  ui();
  debug();
  log();
  driver_vga();
  driver_console();
  driver_x();
  cout << "Hello World!" << endl;
}
