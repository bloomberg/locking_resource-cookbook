require 'spec_helper'

describe Locking_Resource::Helper do
  describe '#process_start_time?' do
    let(:dummy_class) do
      Class.new do
        include Locking_Resource::Helper
      end
    end

    context 'process exists' do
      let(:pgrep_output) { pids.join("\n") + "\n" }
      # create an arbitrary list of plausible PIDs one per line
      let(:pids) { (1..rand(5)).map { rand(0..2**15) } }
      let(:early_idx) { rand(0..pids.length) }
      let(:early_ps_output) { 'Tue Jul 12 14:38:34 2016' }
      let(:late_ps_output) { 'Sat Jul 30 18:48:45 2016' }
      let(:command_string) { 'my command' }
      let(:error_string) { 'TEST: We got an error' }
      def return_stdout(arg)
        # return a list of PIDs for pgrep(1)
        return pgrep_output if arg == "pgrep -f \"#{command_string}\""
        # We must return a known date somewhere so pick a PID to be that
        # and return that early date
        return "#{early_ps_output}\n" if arg.start_with?('ps') && \
                                         arg.end_with?(pids[early_idx].to_s)
        # return our late date for all other PIDs
        return "#{late_ps_output}\n"
      end
  
      it 'raises under pgrep error' do
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

      it 'raises under ps error' do
        fail_pid = rand(0..pids.length - 1)
        # we need to use and_wrap_original since we mutate the double based
        # on the argument passed in per
        # https://www.relishapp.com/rspec/rspec-mocks/v/3-2/docs/
        #         configuring-responses/wrapping-the-original-implementation
        expect(Mixlib::ShellOut).to receive(:new).exactly(fail_pid + 1).times.\
                                 and_wrap_original do |orig, arg|
          puts "YYY #{arg}"
          puts "YYY #{pgrep_output}"
          puts "YYY #{fail_pid}"
          double({ run_command: nil,
            error!: (error_string if \
                     (arg.start_with?('ps') && \
                      arg.end_with?(pids[fail_pid])) or ''),
            exitstatus: 0,
            stdout: return_stdout(arg),
            stderr: (error_string if \
                     (arg.start_with?('ps') && \
                      arg.end_with?(pids[fail_pid])) or ''),
            live_stream: ''
          })
        end
        expect { dummy_class.new.process_start_time(command_string) }.to \
          raise_error(error_string)
      end

      it 'returns the earliest time' do
        expect(Mixlib::ShellOut).to receive(:new) do |arg|
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
