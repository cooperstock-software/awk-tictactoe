#!/usr/bin/awk -f
#
# Console tic-tac-toe in awk: a port of tictactoe.py.
# Run with:   awk -f tictactoe.awk
#
# Written for POSIX awk (no gawk-only features), so it should run in gawk, mawk, macOS/BSD awk and busybox awk.
# The script file needs Unix (LF) line endings.
#
# Differences from the Python version:
#  * Ctrl+C ends the program at once without printing "Exiting..." (awk cannot catch it). The end of input
#    (Ctrl+D, or Ctrl+Z then Enter on Windows) does print it.
#  * If tictactoe.ini cannot be written (read-only folder), awk stops with its own error message instead of
#    printing "Error writing ini file" and carrying on.
#  * awk has no tuples or arrays of arrays, so functions that return two values (has_won_or_tied, choose_move)
#    set globals, and the board is board[row, col], with row and col counted from 0.
#  * Variables listed after a gap in a function's parameter list are that function's local variables.

# ---------------------------------------------------------------------------
# Input, ini file and display
# ---------------------------------------------------------------------------

function trim(s) {
    sub(/^[ \t\r\n]+/, "", s)
    sub(/[ \t\r\n]+$/, "", s)
    return s
}

# Show the prompt and return what was typed, with leading and trailing white space removed.
# At the end of the input, say goodbye and stop.
function ask(prompt,    line) {
    printf "%s", prompt
    fflush()
    if ((getline line < "-") <= 0) {
        print "\n\nExiting..."
        exit 0
    }
    return trim(line)
}

function clear_board(    r, c) {
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            board[r, c] = ""
}

# The ini file is:   [All]
#                    PlayMethod = 1
function read_ini(    line, section, pos, key, val, v) {
    playMethod = PLAYER_FIRST        # default to player first if the ini file is missing or invalid
    section = ""
    while ((getline line < INI_FILE) > 0) {
        line = trim(line)
        if (line ~ /^\[.*\]$/) {
            section = substr(line, 2, length(line) - 2)
            continue
        }
        pos = match(line, /[=:]/)
        if (pos > 0) {
            key = trim(substr(line, 1, pos - 1))
            val = trim(substr(line, pos + 1))
            if (section == "All" && key == "PlayMethod" && val ~ /^[+-]?[0-9]+$/) {
                v = val + 0
                if (v == COMPUTER_FIRST || v == PLAYER_FIRST || v == TWO_PLAYER)
                    playMethod = v
            }
        }
    }
    close(INI_FILE)
}

function write_ini() {
    printf "[All]\nPlayMethod = %d\n\n", playMethod > INI_FILE
    close(INI_FILE)
}

# Prompt for the game mode for the next game, but default to the last used method.
# Return -1 for exit, otherwise return the selected method, update the global
# playMethod variable and save it to the ini file.
function ask_menu(    answer, newMethod) {
    while (1) {
        print "Game Mode"
        print "  1. Computer goes first (I play O)"
        print "  2. I go first (I play X)"
        print "  3. Two players"
        print "  4. Exit"
        answer = ask("Choose 1-4 [" (playMethod + 1) "]: ")
        print ""
        if (answer == "")
            return playMethod
        if (answer == "4")
            return -1
        if (answer == "1" || answer == "2" || answer == "3") {
            newMethod = answer - 1
            if (newMethod != playMethod) {
                playMethod = newMethod
                write_ini()
            }
            return playMethod
        }
        print "Please enter 1, 2, 3 or 4.\n"
    }
}

function print_game(    r, c, line) {
    print "    C1  C2  C3\n"
    for (r = 0; r < 3; r++) {
        line = "R" (r + 1) "  "
        for (c = 0; c < 3; c++)
            line = line (c > 0 ? " | " : "") (board[r, c] == "" ? " " : board[r, c])
        if (r > 0)
            print "   ---+---+---"
        print line
    }
}

# Accepts "row col" or "row,col". Places the letter on the board once a legal square has been entered.
function prompt_for_move(letter,    moveText, answer, n, parts, row, col) {
    if (playMethod == TWO_PLAYER)
        moveText = (letter == "X") ? "first player's" : "second player's"
    else
        moveText = "your"
    while (1) {
        answer = ask("\nEnter " moveText " move for " letter " (row col) or (row,col): ")
        if (answer == "")
            continue
        gsub(/,/, " ", answer)
        n = split(answer, parts)
        if (n != 2 || parts[1] !~ /^[+-]?[0-9]+$/ || parts[2] !~ /^[+-]?[0-9]+$/) {
            print "Invalid input. Please enter two numbers separated by a space or comma."
            continue
        }
        row = parts[1] - 1
        col = parts[2] - 1
        if (!(row >= 0 && row <= 2 && col >= 0 && col <= 2))
            print "Row and column must be between 1 and 3. Try again."
        else if (board[row, col] != "")
            print "That cell is already occupied. Try again."
        else {
            board[row, col] = letter
            print ""
            return
        }
    }
}

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

# print a message for the winner
function print_win_message(letter, partial_message,    winnerText, extraText) {
    # calc some text for the messages
    extraText = ""
    if (playMethod == TWO_PLAYER)
        winnerText = "Player " letter " won"
    else if (letter == computerLetter)
        winnerText = "The computer won"
    else {
        winnerText = "You won"
        extraText = " You beat the computer!"
    }
    print "\n" winnerText " " partial_message "." extraText "\n"
}

function any_empty(    r, c) {
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            if (board[r, c] == "")
                return 1
    return 0
}

# Check for a win by the player with the given letter.
# Sets g_won (whether or not that letter has won) and g_tied (whether or not the game is tied: no more moves left).
# Also shows a message for any win or tie, unless quiet is set.
function has_won_or_tied(letter, quiet,    i) {
    g_won = 1
    g_tied = 0

    # check for win across a row or down a column
    for (i = 0; i < 3; i++) {
        if (board[i, 0] == letter && board[i, 1] == letter && board[i, 2] == letter) {
            if (!quiet)
                print_win_message(letter, "on row " (i + 1))
            return
        }
        if (board[0, i] == letter && board[1, i] == letter && board[2, i] == letter) {
            if (!quiet)
                print_win_message(letter, "on column " (i + 1))
            return
        }
    }

    # check for win down the top left to bottom right diagonal
    if (board[0, 0] == letter && board[1, 1] == letter && board[2, 2] == letter) {
        if (!quiet)
            print_win_message(letter, "on the left-to-right diagonal")
        return
    }

    # check for win down the top right to bottom left diagonal
    if (board[0, 2] == letter && board[1, 1] == letter && board[2, 0] == letter) {
        if (!quiet)
            print_win_message(letter, "on the right-to-left diagonal")
        return
    }

    # No winner, might be tie
    g_won = 0
    if (!quiet) {
        if (nextPlay > 9) {
            g_tied = 1
            print "\nIt's a tie.\n"
        }
    } else
        g_tied = any_empty() ? 0 : 1
}

# ---------------------------------------------------------------------------
# The computer player
# ---------------------------------------------------------------------------

# Value of the position from the point of view of the player with the given letter, who is about to move.
# The board can be changed, but is always returned to its original state.
function calc_score(letter, depth,    opponent, won, tied, result, r, c, value) {
    opponent = (letter == "O") ? "X" : "O"
    # The opponent just moved, so only they can have just completed a line.
    has_won_or_tied(opponent, 1)
    won = g_won
    tied = g_tied
    if (won)
        return -WIN_SCORE + depth      # a later loss is better than an earlier one
    if (tied)
        return 0

    result = -1000000                  # lower than any real score
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            if (board[r, c] == "") {
                board[r, c] = letter
                value = -calc_score(opponent, depth + 1)
                board[r, c] = ""
                if (value > result)
                    result = value
            }
    return result
}

# Finds every equally best square for the given letter: best_count squares, in best_r[1..] and best_c[1..].
# The board is always returned to its original state.
function find_best_moves(letter,    bestValue, opponent, r, c, value) {
    bestValue = -1000000
    best_count = 0
    opponent = (letter == "O") ? "X" : "O"
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)            # try playing in all empty squares
            if (board[r, c] == "") {
                board[r, c] = letter
                value = -calc_score(opponent, 1)
                board[r, c] = ""

                if (value > bestValue) {
                    bestValue = value
                    best_count = 1
                    best_r[1] = r
                    best_c[1] = c
                } else if (value == bestValue) {
                    best_count++
                    best_r[best_count] = r
                    best_c[best_count] = c
                }
            }
}

# Picks the computer's move. Call only when at least one square is empty.
# Sets mv_row and mv_col to the position to make the move in for that player.
function choose_move(letter,    pick) {
    find_best_moves(letter)
    # choose at random among equally good moves, so the computer varies its play
    pick = 1 + int(rand() * best_count)
    mv_row = best_r[pick]
    mv_col = best_c[pick]
}

# ---------------------------------------------------------------------------
# The game
# ---------------------------------------------------------------------------

function play_game(    k, r, c, letter) {
    if (playMethod == COMPUTER_FIRST) {
        computerLetter = "X"
        playerLetter = "O"
        # do a random first move for the computer in a corner
        k = int(rand() * 4)
        r = (k < 2) ? 0 : 2
        c = (k % 2 == 0) ? 0 : 2
        print "Here is the computer's move as " computerLetter "\n"
        board[r, c] = computerLetter
        nextPlay++
    } else if (playMethod == PLAYER_FIRST) {
        computerLetter = "O"
        playerLetter = "X"
    }

    print_game()
    while (1) {
        # it's always a player's turn at this point
        letter = (nextPlay % 2 == 1) ? "X" : "O"
        prompt_for_move(letter)
        nextPlay++
        print_game()
        has_won_or_tied(letter)
        if (g_won || g_tied)
            return
        if (playMethod == TWO_PLAYER)
            continue

        # computer's turn
        choose_move(computerLetter)
        board[mv_row, mv_col] = computerLetter
        print "\nHere is the computer's move as " computerLetter "\n"
        print_game()
        nextPlay++
        has_won_or_tied(computerLetter)
        if (g_won || g_tied)
            return
    }
}

function init() {
    WIN_SCORE = 10
    # playMethod values
    COMPUTER_FIRST = 0
    PLAYER_FIRST = 1
    TWO_PLAYER = 2
    INI_FILE = "tictactoe.ini"
    srand()
}

function main() {
    # read the ini file to get the last used play method
    read_ini()

    while (1) {
        nextPlay = 1
        clear_board()
        playMethod = ask_menu()
        if (playMethod == -1)
            exit 0
        play_game()
    }
}

BEGIN { init(); main() }
