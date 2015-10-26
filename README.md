This program adds default parameter values to a Spice/Spectre model
(and converts to LTspice format)

Usage:
     ruby spice_addd.rb input_model_file[, default_parameters_file]

Default parameters are added to the end of a model descriptin given in input_model_file.
Please edit the output by hand if necessary (eg. prepend + to make continuation.)

default_parameters_file stores default parameter value pair separated
by space, command or equal sign in each line.
Parameter names must be in upper case (but you can change it in the program).

Note: This program is a quick patch whose fragments are gathered from another system. So,
      there might be many unused methods included. 

I know the program could have been much simpler, but it was much simpler to develop
this way for me.