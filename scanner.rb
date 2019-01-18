# Written by Brandon Allard of University of Rochester for CSC 254

require 'set'

class Token 
    attr_accessor :type, :value

    def initialize(type, value)
        @type = type
        @value = value
    end

    def to_s
        "< "+@type.to_s+" , "+@value.to_s+" >"
    end

    def ==(token)
        return token != nil && @type == token.type && @value == token.value
    end
end

class DFA
    def initialize(dfa)
        # A few correctness checks could be implemented here..
        @alphabet = dfa[:alphabet]
        @states = dfa[:states]
        @start_state = dfa[:start_state]
        @end_state = dfa[:end_state]
        @transitions = dfa[:transitions]
    end

    # Returns a value or nil
    def next(char_stream)
        # Set starting conditions
        state = @start_state
        output = ""
        
        # Loop until endstate is reached
        while current_char = char_stream.peek
            idx = @transitions[state].index { |x|
               x[0] == :all ||x[0].include?(current_char)
            }
            if idx == nil
                break
            else
                output << char_stream.next
                state = @transitions[state][idx][1]
            end
        end

        # Return a called function or nil
        return (@end_state[state] != nil) ? @end_state[state].call(output) : nil
    end
end

class Scanner
    def initialize(file_path)
        # Attempt to open file
        @file = File.open(file_path, "r")
        @chars = @file.each_char

        # Define subsets in the alphabet the DFA accepts
        letter_chars = %w(a b c d e f g h i j k l m n o p q r s t u 
                           v w x y z A B C D E F G H I J K L M N O P 
                           Q R S T U V W X Y Z _).to_set
        number_chars = %w(1 2 3 4 5 6 7 8 9 0).to_set
        symbol_chars = %w(( ) { } , ; + - * / = < > ! & | # [ ]).to_set
        space = [" ", "\v", "\t"].to_set
        eol = ["\n", "\r"].to_set
        string = ['"'].to_set
        reserved = %w(int void if else while return continue break scanf printf).to_set

        # Define the DFA that's used to tokenize language
        @dfa = DFA.new({
            :alphabet => letter_chars | number_chars | symbol_chars | 
                         space | eol | string,
            :states => [:start, :identifier, :comment, :symbol, :number, :string,
                        :equal, :forward_slash, :or, :and, :symbol_end, :error,
                        :quote_end],
            :start_state => :start,
            :end_state => {
                :number        => lambda { |n| Token.new(:number, n.strip) },
                :identifier         => lambda { |n| Token.new(
                                    (reserved.member? n.strip) ? :reserved : :identifier, n.strip) },
                :comment_end   => lambda { |n| Token.new(:comment, n.strip) },
                :symbol        => lambda { |n| Token.new(:symbol, n.strip) },
                :symbol_end    => lambda { |n| Token.new(:symbol, n.strip) },
                :equal         => lambda { |n| Token.new(:symbol, n.strip) },
                :or            => lambda { |n| Token.new(:symbol, n.strip) },
                :and           => lambda { |n| Token.new(:symbol, n.strip) },
                :forward_slash => lambda { |n| Token.new(:symbol, n.strip) },
                :quote_end     => lambda { |n| Token.new(:string, n) },
                :error         => lambda { |n| Token.new(:comment,  "Invalid token: "+n) } },
            :transitions => {
                :start => [
                    [number_chars, :number],
                    [letter_chars, :identifier],
                    ["#", :comment],
                    ["/", :forward_slash],
                    [%w(= < > !).to_set, :equal],
                    ["&", :and],
                    ["|", :or],
                    [symbol_chars, :symbol],
                    [string, :string],
                    [space | eol, :start],
                    [:all, :error] ],
                :number => [
                    [number_chars, :number],
                    [letter_chars | string, :error] ],
                :symbol => [],
                :identifier => [
                    [letter_chars | number_chars, :identifier],
                    [string, :error] ],
                :comment => [
                    [eol, :comment_end],
                    [:all, :comment] ],
                :string => [
                    [string, :quote_end],
                    [:all, :string] ],
                :equal => [
                    ["=", :symbol_end] ],
                :or => [
                    ["|", :symbol_end] ],
                :and => [
                    [["&"].to_set, :symbol_end] ],
                :forward_slash => [
                    ["/", :comment] ],
                :symbol_end => [],
                :quote_end => [],
                :comment_end => [],
                :error => []
            }
        })
        @current_token = nil
    end

    def next
        unless @current_token != nil
            begin
                return @dfa.next(@chars)
            rescue StopIteration
                return Token.new(:eof, "")
            else
                exit
            end
        else
            current = @current_token.clone
            @current_token = nil
            return current
        end
    end

    def peek
        if @current_token == nil
            @current_token = self.next
        end

        return @current_token
    end
    def peeka
        if @current_token == nil
            @current_token = self.next
        end
        puts "current token #{@current_token}."

        return @current_token
    end
end

