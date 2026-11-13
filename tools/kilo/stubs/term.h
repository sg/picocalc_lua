#pragma once
#include <stdbool.h>
void term_clear();
int term_get_width();
int term_get_height();
int term_get_x();
int term_get_y();
void term_set_blinking_cursor(bool enabled);
