// Cost per instruction in microseconds.
// Taken from https://jackson-s.me/2019/07/13/Chip-8-Instruction-Scheduling-and-Frequency.html

pub const CLEAR_SCREEN = 109;
pub const RETURN = 105;
pub const JUMP = 105;
pub const CALL = 105;
pub const SKIP_3X = 55;
pub const SKIP_4X = 55;
pub const SKIP_5X = 73;
pub const SET_REGISTER = 27;
pub const ADD = 45;
pub const ARITHMETIC = 200;
pub const SKIP_9X = 73;
pub const SET_INDEX = 55;
pub const JUMP_WITH_OFFSET = 105;
pub const GET_RANDOM = 164;
pub const DRAW = 22734;
pub const CHECK_KEY = 73;
pub const GET_DELAY_TIMER = 45;
pub const GET_KEY = 0;
pub const SET_DELAY_TIMER = 45;
pub const SET_SOUND_TIMER = 45;
pub const ADD_TO_INDEX = 86;
pub const SET_FONT = 91;
pub const BCD = 927;
pub const STORE_MEM = 605;
pub const LOAD_MEM = 605;
