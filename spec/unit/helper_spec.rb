require 'spec_helper'
require 'pry'

describe Locking_Resource::Helper do
  describe '#create_node' do
    let(:dummy_class) do
      Class.new do
        include Locking_Resource::Helper
      end.new
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path/a_node' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:my_data) { 'my_data' }
      let(:exception_str) { 'Error from test - should be puts()' }
    
      it 'swallows exception and returns false' do
        expect(STDOUT).to receive(:puts).with(exception_str)
        expect(Zookeeper).to receive(:new).and_raise(exception_str)
        expect(dummy_class.create_node(quorum_hosts=hosts, path=node_path, data=my_data)).to match(false)
      end
    
      it 'swallows exception and returns true' do
        dbl = double({ connected?: true,
                   create: {"rc".to_sym => 0}})
        expect(Zookeeper).to receive(:new) { dbl }
        expect(STDOUT).to receive(:puts).with(exception_str)
        expect(dbl).to receive(:closed?).and_raise(exception_str)
        expect(dummy_class.create_node(quorum_hosts=hosts, path=node_path, data=my_data)).to match(true)
      end
    
      it 'returns true if node created' do
        expect(Zookeeper).to receive(:new) do
          double({ connected?: true,
                   create: {"rc".to_sym => 0},
                   closed?: true })
        end
        expect(dummy_class.create_node(quorum_hosts=hosts, path=node_path, data=my_data)).to match(true)
      end
    end
  end 

  describe '#lock_matches?' do
    let(:dummy_class) do
      Class.new do
        include Locking_Resource::Helper
      end.new
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path/a_node' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:my_data) { 'my_data' }
      let(:exception_str) { 'Error from test - should be puts()' }
      let(:dbl) { double() }
    
      it 'returns true if lock matches' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times{ dbl }
        expect(dbl).to receive(:connected?).exactly(1).times{ true }
        expect(dbl).to receive(:get).with(:path => node_path).exactly(1).times{ {:data => my_data} }
        expect(dbl).to receive(:closed?).exactly(1).times{ false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.lock_matches?(quorum_hosts=hosts, path=node_path, data=my_data)).to match(true)
      end
    
      it 'returns false if lock does not match' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times{ dbl }
        expect(dbl).to receive(:connected?).exactly(1).times{ true }
        expect(dbl).to receive(:get).with(:path => node_path).exactly(1).times{ {:data => 'random stuff'} }
        expect(dbl).to receive(:closed?).exactly(1).times{ false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.lock_matches?(quorum_hosts=hosts, path=node_path, data=my_data)).to match(false)
      end
    
      it 'swallows an exception in Zk.get and returns false' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times{ dbl }
        expect(dbl).to receive(:connected?).exactly(1).times{ true }
        expect(dbl).to receive(:get).with(:path => node_path).exactly(1).times.and_raise(exception_str)
        expect(STDOUT).to receive(:puts).with(exception_str)
        expect(dbl).to receive(:closed?).exactly(1).times{ false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.lock_matches?(quorum_hosts=hosts, path=node_path, data=my_data)).to match(false)
      end
    
      it 'swallows an exception in Zk.close and returns true' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times{ dbl }
        expect(dbl).to receive(:connected?).exactly(1).times{ true }
        expect(dbl).to receive(:get).with(:path => node_path).exactly(1).times{ {:data => my_data} }
        expect(dbl).to receive(:closed?).exactly(1).times{ false }
        expect(dbl).to receive(:close).exactly(1).times.and_raise(exception_str)
        expect(STDOUT).to receive(:puts).with(exception_str)
        expect(dummy_class.lock_matches?(quorum_hosts=hosts, path=node_path, data=my_data)).to match(true)
      end
    end
  end

  describe '#process_restarted_after_failure?' do
    let(:dummy_class) do
      Class.new do
        include Locking_Resource::Helper
      end.new
    end

    context 'plausible ps output and command name' do
      let(:early_ps_output) { 'Tue Jul 12 14:38:34 2016' }
      let(:late_ps_output) { 'Sat Jul 30 18:48:45 2016' }
      let(:command_string) { 'my command' }
    
      it 'returns true if ps says process started after time passed in' do
        expect(dummy_class).to receive(:process_start_time).with('my command') do
          late_ps_output
        end
        expect(dummy_class.process_restarted_after_failure?(early_ps_output, command_string)).to match(true)
      end

      it 'returns false if ps says process started before time passed in' do
        expect(dummy_class).to receive(:process_start_time).with('my command') do
          early_ps_output
        end
        expect(dummy_class.process_restarted_after_failure?(late_ps_output, command_string)).to match(false)
      end
    end
  end

  describe '#process_start_time?' do
    let(:dummy_class) do
      Class.new do
        include Locking_Resource::Helper
      end
    end

    context 'random pids and early index with reasonable ps and command' do
      # create an arbitrary list of plausible PIDs one per line
      let(:pids) { (5..rand(10)).map { rand(1..2**15) } }
      let(:early_idx) { rand(0..pids.length-1) }
      let(:early_ps_output) { 'Tue Jul 12 14:38:34 2016' }
      let(:late_ps_output) { 'Sat Jul 30 18:48:45 2016' }
      let(:pgrep_output) { pids.join("\n") + "\n" }
      let(:command_string) { 'my command' }
      let(:error_string) { 'TEST: We got an error' }

      def return_stdout(arg)
        puts "XXX early_idx #{early_idx}; PIDs: #{pids}"
        puts "XXX0 return_stdout Arg: #{arg}"
        puts "XXX1 pgrep output: #{pgrep_output}" if arg == "pgrep -f \"#{command_string}\""
        # return a list of PIDs for pgrep(1)
        return pgrep_output if arg == "pgrep -f \"#{command_string}\""
        # We must return a known date somewhere so pick a PID to be that
        # and return that early date
        puts "XXX1 Returning early" if arg.start_with?('ps') && \
                                  arg.end_with?(pids[early_idx].to_s)
        return "#{early_ps_output}\n" if arg.start_with?('ps') && \
                                         arg.end_with?(pids[early_idx].to_s)
        # return our late date for all other PIDs
        puts "XXX1 Returning late"
        return "#{late_ps_output}\n"
      end
 
      it 'raises under pgrep error' do
        puts "XXX early_idx #{early_idx}; PIDs: #{pids}"
        expect(Mixlib::ShellOut).to receive(:new) do |arg|
          double({ run_command: nil,
            error!: '',
            exitstatus: 0,
            stdout: '',
            stderr: error_string,
            live_stream: ''
          })
        end.exactly(1).times
        expect { dummy_class.new.process_start_time(command_string) }.to \
          raise_error(error_string)
      end

# Can not seem to get standard out stub to work
# Randomized with seed 15068
#
#Locking_Resource::Helper
#  #process_start_time?
#    process exists
#XXX early_idx 0; PIDs: [29371, 6114]
#XXX3 Happy run - earliest time!  
#XXX early_idx 0; PIDs: [29371, 6114]
#XXX0 return_stdout Arg: pgrep -f "my command"
#XXX1 pgrep output: 29371
#6114
#XXXlib pgrep , XXX 29371
#6114
#XXX3 Happy run - earliest time!  
#XXX early_idx 0; PIDs: [29371, 6114]
#XXX0 return_stdout Arg: ps --no-header -o lstart 29371
#XXX1 Returning early
#XXXlib ps , XXX Tue Jul 12 14:38:34 2016
#XXX3 Happy run - earliest time!
#XXX early_idx 0; PIDs: [29371, 6114]
#XXX0 return_stdout Arg: ps --no-header -o lstart 6114
#XXX1 Returning late
#XXXlib ps , XXX Sat Jul 30 18:48:45 2016
#      returns the earliest time
#XXX early_idx ; PIDs: []
#Early idx:
#      raises under ps error (FAILED - 1)
#
#Failures:
#
#  1) Locking_Resource::Helper#process_start_time? process exists raises under ps error
#     Failure/Error:
#       expect { dummy_class.new.process_start_time(command_string) }.to \
#         raise_error(error_string)
#
#       expected Exception with "TEST: We got an error", got #<NoMethodError: undefined method `+' for nil:NilClass> with backtrace:
#         # ./spec/unit/helper_spec.rb:64:in `block (5 levels) in <top (required)>'
#         # ./libraries/helpers.rb:175:in `process_start_time'
#         # ./spec/unit/helper_spec.rb:80:in `block (5 levels) in <top (required)>'
#         # ./spec/unit/helper_spec.rb:80:in `block (4 levels) in <top (required)>'
#     # ./spec/unit/helper_spec.rb:80:in `block (4 levels) in <top (required)>'
#

#     it 'raises under ps error' do
#       puts "XXX early_idx #{early_idx}; PIDs: #{pids}"
#       # we need to use and_wrap_original since we mutate the double based
#       # on the argument passed in per
#       # https://www.relishapp.com/rspec/rspec-mocks/v/3-2/docs/
#       #         configuring-responses/wrapping-the-original-implementation
#       counter = 1
#       puts "Early idx: #{rand(0..pids.length-1)}"
#       expect(Mixlib::ShellOut).to receive(:new).\
#                                and_wrap_original do |orig, arg|
#         puts "XXX2 Expected #{early_idx + 1}; #{counter}"
#         counter += 1
#         puts "XXX2 shellout arg: #{arg}|"
#         puts "XXX2 shellout pgrep: #{return_stdout(arg)}|" if arg.start_with?('pgrep')
#         puts "XXX2 shellout ps: #{return_stdout(arg)}|" if arg.start_with?('ps')
#         puts "XXX2 expected fail pid index: #{early_idx}|"
#         double({ run_command: nil,
#           error!: (arg.start_with?('ps') && \
#                     arg.end_with?(pids[early_idx])) ? error_string : '',
#           exitstatus: 0,
#           stdout: return_stdout(arg),
#           stderr: (arg.start_with?('ps') && \
#                     arg.end_with?(pids[early_idx])) ? error_string : '',
#           live_stream: ''
#         })
#       end
#       expect { dummy_class.new.process_start_time(command_string) }.to \
#         raise_error(error_string)
#     end

      it 'returns the earliest time' do
        puts "XXX early_idx #{early_idx}; PIDs: #{pids}"
        expect(Mixlib::ShellOut).to receive(:new) do |arg|
          puts "XXX3 Happy run - earliest time!"
          double({ run_command: nil,
            error!: '',
            exitstatus: 0,
            stdout: return_stdout(arg),
            stderr: '',
            live_stream: ''
          })
        end.exactly(pids.length+1).times
        expect(dummy_class.new.process_start_time(command_string)).to \
          eq(Time.parse(early_ps_output).to_s)
      end
    end
  end
end
