#!/usr/bin/ruby

require_relative 'scanner'

class Parser
  class ParseError < StandardError
  end

  attr_reader :type_count

  # An enumerator that contains lines that should be parsed.
  def initialize(line_enum)
    @enum = Scanner.new(line_enum)
    @type_count = {
      variable: 0,
      function: 0,
      statement: 0
    }

    @local_var = 0
    @global_var = 0
    @local_index = 0
    @global_index = 0
    @de_global_index = 0
    @local = Array[]
    @global = Array[]
    @instruction = %w()
    @if_count = 0
    @global_array_bool=false
    @while_bool=false
    @while_count=0
  end

  # Parses the enumerator that was passed to the constructor.
  # Returns true if enumerator successfully parses.
  # Throws Parser::ParseError if enumerator does not parse
  def parse
    return false if skip_meta_statements
    program
    match(:eof)
    true
  end

  # Helper function that moves the tokenizer forward if the next token matches
  # the passed in tokens.
  #
  # tokens can be either an Array of Tokens, a Symbol or a Token.
  # If tokens is an array the next token must be in the array.
  # If tokens is a Symbol the type of the next token must match the symbol.
  # If tokens is a Token the next token must be equal.
  #
  # Throws Parser::ParseError is the next token does not match
  def match(tokens)
    fail ParseError, "Unexpected token #{@enum.peek}, expected #{tokens}" unless
      case tokens
      when Symbol
        tokens == @enum.peek.type
      when Token
        tokens == @enum.peek
      when Array
        tokens.include? @enum.peek
      else
        fail ArgumentError, 'Not a symbol or array'
      end
    @enum.next
    skip_meta_statements
  end

  # Skip meta statements as they are not part of the grammar
  def skip_meta_statements
    while @enum.peek.type == :comment
      @instruction.push(@enum.peek.value+"\n")
      @enum.next
    end
  rescue StopIteration
    false
  end

  # helper function to match a semicolon
  def semicolon
    @instruction.push(@enum.peek.value+"\n")
    match(Token.new(:symbol, ';'))
  end

  # helper function to match a comma
  def comma
    match(Token.new(:symbol, ','))
  end

  # <program> --> void ID ( <parameter_list> ) <func_tail> <func_list>
  #             | int ID <program_tail>
  #             | epsilon
  def program
    case @enum.peek.value
    when 'void'
      @instruction.push(@enum.peek.value)
      match(Token.new(:reserved, 'void'))
      @instruction.push(@enum.peek.value)
      match(:identifier)
      @instruction.push(@enum.peek.value)
      match(Token.new(:symbol, '('))
      parameter_list
      @instruction.push(@enum.peek.value)
      match(Token.new(:symbol, ')'))
      func_tail
      func_list
    when 'int'
      if @global_var!=0
        @instruction.push("int global["+@global_var.to_s+"];\n")
      end
      @instruction.delete_if{|item| item.start_with?("int global") and item != @instruction.last}
      @instruction.push(@enum.peek.value)
      match(Token.new(:reserved, 'int'))
      @instruction.push(@enum.peek.value)
      @global.push(@enum.peek.value)
      @de_global_index = @global.index(@enum.peek.value)
      match(:identifier)
      program_tail
    end
  end

  # <program_tail> --> ( <paramter_list> ) <func_tail> <func_list>
  #                  | <id_tail> <program_decl_tail>
  def program_tail
    if @enum.peek.value == '('
      @instruction.push(@enum.peek.value)
      @global.delete_at(@de_global_index)
      match(Token.new(:symbol, '('))
      parameter_list
      @instruction.push(@enum.peek.value)
      match(Token.new(:symbol, ')'))
      func_tail
      func_list
    else
      id_tail
      program_decl_tail
    end
    @global_array_bool=false
  end

  # <program_decl_tail> --> , <id_list> ; <program>
  #                       | ; <program>
  def program_decl_tail
    @global_var += 1
    case @enum.peek.value
    when ','
      comma
      global_id_list
      semicolon
      @instruction.delete(@instruction.last)
      @instruction.delete(@instruction.last)
      @instruction.delete(@instruction.last)
      program
    when ';'
      semicolon
      unless @global_array_bool
        @instruction.delete(@instruction.last)
        @instruction.delete(@instruction.last)
        @instruction.delete(@instruction.last)
      end
      program
    else
      fail ParseError, "Expected , or ;, found #{@enum.peek.value}"
    end
    @type_count[:variable] += 1
  end

  # <func_list> --> <func> <func_list>
  #               | epsilon
  def func_list
    if %w(int void).include? @enum.peek.value
      func
      func_list
    end
  end

  # <func> --> <func_decl> <func_tail>
  def func
    func_decl
    func_tail
  end

  # <func_tail> --> ;
  #               | { <data_decls> <statements> }
  def func_tail
    case @enum.peek.value
    when ';'
      semicolon
    when '{'
      @instruction.push(@enum.peek.value+"\n")
      match(Token.new(:symbol, '{'))
      @type_count[:function] += 1
      if @local_var!=0
        @instruction.push('int local['+(@local_var).to_s+"];\n")
      end
      data_decls
      statements
      @instruction.push(@enum.peek.value+"\n")
      match(Token.new(:symbol, '}'))
      @local_var=0
      @local.clear
    else
      fail ParseError, "Expected ; or {, found #{@enum.peek.value}"
    end
  end

  # <func_decl> --> <type_name> ID ( <parameter_list> )
  def func_decl
    type_name
    @instruction.push(@enum.peek.value)
    match(:identifier)
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '('))
    parameter_list
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, ')'))
  end

  # <type_name> --> int
  #               | void
  def type_name
    @instruction.push(@enum.peek.value)
    match(%w(int void).map { |t| Token.new(:reserved, t) })
  end

  # <parameter_list> --> void
  #                    | int ID <parameter_list_tail>
  #                    | epsilon
  def parameter_list
    case @enum.peek.value
    when 'void'
      @instruction.push(@enum.peek.value)
      match(Token.new(:reserved, 'void'))
    when 'int'
      @instruction.push(@enum.peek.value)
      match(Token.new(:reserved, 'int'))
      @instruction.push(@enum.peek.value)
      match(:identifier)
      parameter_list_tail
    end
  end

  # <parameter_list_tail> --> , int ID <parameter_list_tail>
  #                         | epsilon
  def parameter_list_tail
    if @enum.peek.value == ','
      @instruction.push(@enum.peek.value)
      comma
      @instruction.push(@enum.peek.value)
      match(Token.new(:reserved, 'int'))
      @instruction.push(@enum.peek.value)
      match(:identifier)
      parameter_list_tail
    end
  end

  # <data_decls> --> int <id_list> ; <data_decls>
  #                | epsilon
  def data_decls
    if @enum.peek.value == 'int'
      #@instruction.push(@enum.peek.value)
      match(Token.new(:reserved, 'int'))
      local_id_list
      @instruction.push('int local['+(@local_var).to_s+"]")
      #@instruction.delete_if{|item| item.start_with?("int local") and item != @instruction.last}
      semicolon
      #@instruction.delete(@instruction.last)
      data_decls
    end
  end

  def global_id_list
    @global_var += 1
    @global.push(@enum.peek.value)
    match(:identifier)
    id_tail
    global_id_list_tail
  end
  # <id_list> --> ID <id_tail> <id_list_tail>
  def local_id_list
    #@type_count[:variable] += 1
    @local_var += 1
    @local.push(@enum.peek.value)
    match(:identifier)
    id_tail
    local_id_list_tail
  end

  # <id_list_tail> --> , <id_list>
  #                  | epsilon
  def global_id_list_tail
    if @enum.peek.value == ','
      comma
      global_id_list
    end
  end

  def local_id_list_tail
    if @enum.peek.value == ','
      comma
      local_id_list
    end
  end

  # <id_tail> --> [ <expression> ]
  #             | epsilon
  def id_tail
    if @enum.peek.value == '['
      @global_array_bool = true
      @instruction.delete(@instruction.last)
      @instruction.push("global")
      @instruction.push(@enum.peek.value)
      match(Token.new(:symbol, '['))
      expression
      @instruction.push(@enum.peek.value)
      match(Token.new(:symbol, ']'))
    end
  end

  # <block_statements> --> { <statements> }
  def block_statements
    #@instruction.push(@enum.peek.value+"\n")
    match(Token.new(:symbol, '{'))
    statements
    #@instruction.push(@enum.peek.value+"\n")
    match(Token.new(:symbol, '}'))
  end

  # <statements> --> <statement> <statements>
  #                | epsilon
  def statements
    if %i(identifier reserved).include? @enum.peek.type
      @type_count[:statement] += 1
      statement
      statements
    end
  end

  # <statement> --> <break_statement>
  #               | <continue_statement>
  #               | <if_statement>
  #               | <printf_func_call>
  #               | <return_statement>
  #               | <scanf_func_call>
  #               | <while_statement>
  #               | ID <statement_tail>
  def statement
    case @enum.peek.value
    when 'break'
      break_statement
    when 'continue'
      continue_statement
    when 'if'
      if_statement
    when 'printf'
      printf_func_call
    when 'return'
      return_statement
    when 'scanf'
      scanf_func_call
    when 'while'
      while_statement
    else
      if @local.include?(@enum.peek.value)
        @instruction.push('local[' + @local.index(@enum.peek.value).to_s + ']')
      elsif @global.include?(@enum.peek.value)
        @instruction.push('global[' + @global.index(@enum.peek.value).to_s + ']')
      else
        @instruction.push(@enum.peek.value)
      end
      match(:identifier)
      statement_tail
    end
  end

  # <statement_tail> --> <general_func_call>
  #                    | <assignment>
  def statement_tail
    if @enum.peek.value == '('
      general_func_call
    else
      assignment
    end
  end

  # <general_func_call> --> ( <expr_list> ) ;
  def general_func_call
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '('))
    expr_list
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, ')'))
    semicolon
  end

  # <assignment> --> <id_tail> = <expression> ;
  def assignment
    id_tail
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '='))
    expression
    semicolon
    #@instruction.push(";")
    #@instruction.push("\n")
  end

  # <printf_func_call> --> printf ( string <print_func_call_tail>
  def printf_func_call
    @instruction.push(@enum.peek.value)
    match(Token.new(:reserved, 'printf'))
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '('))
    @instruction.push(@enum.peek.value)
    match(:string)
    printf_func_call_tail
  end

  # <printf_func_call_tail> --> ) ;
  #                           | , <expression> ) ;
  def printf_func_call_tail
    case @enum.peek.value
    when ','
      @instruction.push(@enum.peek.value)
      comma
      expression
      @instruction.push(@enum.peek.value)
      match(Token.new(:symbol, ')'))
      semicolon
    when ')'
      @instruction.push(@enum.peek.value)
      match(Token.new(:symbol, ')'))
      semicolon
    else
      fail ParseError, "Expected ',' or ')'. Found #{@enum.peek}"
    end
  end

  # <scanf_func_call> --> scanf ( string , & <expression> ) ;
  def scanf_func_call
    @instruction.push(@enum.peek.value)
    match(Token.new(:reserved, 'scanf'))
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '('))
    @instruction.push(@enum.peek.value)
    match(:string)
    comma
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '&'))
    expression
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, ')'))
    semicolon
  end

  # returns true if the next token is in the first set for expression
  def in_first_of_expression
    case @enum.peek.type
    when :identifier, :number
      true
    when :symbol
      ['(', '-'].include? @enum.peek.value
    else
      false
    end
  end

  # <expr_list> --> <expression> <expr_list_tail>
  #               | epsilon
  def expr_list
    if in_first_of_expression
      expression
      expr_list_tail
    end
  end

  # <expr_list_tail> --> , <expression> <expr_list_tail>
  #                    | epsilon
  def expr_list_tail
    if @enum.peek.value == ','
      @instruction.push(@enum.peek.value)
      comma
      expression
      expr_list_tail
    end
  end

  # <if_statement> --> if ( <condition_expression> ) <block_statements>
  #                       <else_statement>
  def if_statement
    @instruction.push(@enum.peek.value)
    match(Token.new(:reserved, 'if'))
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '('))
    condition_expression
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, ')'))
    @if_count += 1
    @instruction.push('goto state_'+@if_count.to_s+';'+"\n"+'goto state_'+(@if_count+1).to_s+';'+"\n"+' state_'+@if_count.to_s+':;'+"\n")
    @if_count += 1
    block_statements
    @instruction.push(' state_'+@if_count.to_s+":0;\n")
    else_statement
  end

  # <else_statement> --> else <block_statements>
  #                    | epsilon
  def else_statement
    if @enum.peek.value == 'else'
      @instruction.push('state_'+(@if_count+1).to_s+":\n")
      match(Token.new(:reserved, 'else'))
      block_statements
    end
  end

  # <condition_expression> --> <condition> <condition_expression_tail>
  def condition_expression
    condition
    condition_expression_tail
  end

  # <condition_expression_tail> --> <condition_op> <condition>
  #                               | epsilon
  def condition_expression_tail
    if %(&& ||).include? @enum.peek.value
      condition_op
      condition
    end
  end

  # <condition_op> --> &&
  #                  | ||
  def condition_op
    @instruction.push(@enum.peek.value)
    match(%w(&& ||).map { |t| Token.new(:symbol, t) })
  end

  # <condition> --> <expression> <comparison_op> <expression>
  def condition
    expression
    comparison_op
    expression
  end

  # <comparison_op> --> ==
  #                   | !=
  #                   | >
  #                   | >=
  #                   | <
  #                   | <=
  def comparison_op
    @instruction.push(@enum.peek.value)
    match(%w(== != > >= < <=).map { |t| Token.new(:symbol, t) })
  end

  # <while_statement> --> while ( <condition_expression> ) <block_statements>
  def while_statement
   #@instruction.push(@enum.peek.value)
    @while_bool = true
    @while_count+=1
    @instruction.push("start_while_"+@while_count.to_s+":;\nif")
    match(Token.new(:reserved, 'while'))
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, '('))
    condition_expression
    @instruction.push(@enum.peek.value)
    match(Token.new(:symbol, ')'))
    @instruction.push(" goto while_"+@while_count.to_s+";\ngoto end_while_"+@while_count.to_s+";\nwhile_"+@while_count.to_s+":;\n")
    block_statements
    if @while_bool==false
        @while_count=@while_count-1
    end
    @instruction.push("goto start_while_"+@while_count.to_s+";\nend_while_"+@while_count.to_s+":0;\n")
    @while_bool=false
  end

  # <return_statement> --> return <return_statement_tail>
  def return_statement
    @instruction.push(@enum.peek.value)
    match(Token.new(:reserved, 'return'))
    return_statement_tail
  end

  # <return_statement_tail> --> <expression> ;
  #                           | ;
  def return_statement_tail
    expression if @enum.peek != Token.new(:symbol, ';')
    semicolon
    #@instruction.push(";")
    #@instruction.push("\n")
  end

  # <break_statement> ---> break ;
  def break_statement
    if @while_bool
        @instruction.push("goto end_while_"+@while_count.to_s)
    else
        @instruction.push(@enum.peek.value)
    end
    match(Token.new(:reserved, 'break'))
    semicolon
  end

  # <continue_statement> ---> continue ;
  def continue_statement
    @instruction.push(@enum.peek.value)
    match(Token.new(:reserved, 'continue'))
    semicolon
  end

  # <expression> --> <term> <expression_tail>
  def expression
    term
    expression_tail
  end

  # <expression_tail> --> <addop> <term> <expression_tail>
  #                     | epsilon
  def expression_tail
    if %w(+ -).include? @enum.peek.value
      addop
      term
      expression_tail
    end
  end

  # <addop> --> +
  #           | -
  def addop
    @instruction.push(@enum.peek.value)
    match(%w(+ -).map { |t| Token.new(:symbol, t) })
  end

  # <term> --> <factor> <term_tail>
  def term
    factor
    term_tail
  end

  # <term_tail> --> <mulop> <factor> <term_tail>
  #               | epsilon
  def term_tail
    if %w(* /).include? @enum.peek.value
      mulop
      factor
      term_tail
    end
  end

  # <mulop> --> *
  #           | /
  def mulop
    @instruction.push(@enum.peek.value)
    match(%w(* /).map { |t| Token.new(:symbol, t) })
  end

  # <factor> --> ID <factor_tail>
  #            | NUMBER
  #            | - NUMBER
  #            | ( <expression> )
  def factor
    case @enum.peek.type
    when :number
      @instruction.push(@enum.peek.value)
      match(:number)
    when :symbol
      case @enum.peek.value
      when '('
        @instruction.push(@enum.peek.value)
        match(Token.new(:symbol, '('))
        expression
        @instruction.push(@enum.peek.value)
        match(Token.new(:symbol, ')'))
      when '-'
        @instruction.push(@enum.peek.value)
        match(Token.new(:symbol, '-'))
        @instruction.push(@enum.peek.value)
        match(:number)
      else
        fail ParseError, "Unexpected token #{@enum.peek}"
      end
    when :identifier
      if @local.include?(@enum.peek.value)
        @instruction.push('local[' + @local.index(@enum.peek.value).to_s + ']')
      elsif @global.include?(@enum.peek.value)
        if @global_array_bool==true
          @instruction.push('global')
        else
          @instruction.push('global[' + @global.index(@enum.peek.value).to_s + ']')
        end
      else
        @instruction.push(@enum.peek.value)
      end
      match(:identifier)
      factor_tail
    else
      fail ParseError, "Unexpected token #{@enum.peek}"
    end
  end

  # <factor_tail> --> [ <expression> ]
  #                 | ( <expr_list> )
  #                 | epsilon
  def factor_tail
    if @enum.peek.type == :symbol
      case @enum.peek.value
      when '['
        @instruction.push(@enum.peek.value)
        match(Token.new(:symbol, '['))
        expression
        @instruction.push(@enum.peek.value)
        match(Token.new(:symbol, ']'))
      when '('
        @instruction.push(@enum.peek.value)
        match(Token.new(:symbol, '('))
        expr_list
        @instruction.push(@enum.peek.value)
        match(Token.new(:symbol, ')'))
      end
    end
  end

  def instruction
    length = @instruction.length-1
    for i in 0..length do
      print "#{@instruction[i]}" + " "
    end
  end

end

#parser = Parser.new('/Users/shinshukuni/Desktop/a4_tests/automaton.c')
parser= Parser.new(ARGV[0])
parser.parse
parser.instruction
