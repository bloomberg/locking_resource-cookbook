require 'spec_helper'
require 'time'

describe LockingResource::Helper do
  describe '#create_node' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end.new
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path/a_node' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:my_data) { 'my_data' }
      let(:exception_str) { 'Error from test - should be logged' }

      it 'creates necessary path and returns true' do
        expect(dummy_class).to receive(:get_node_data) \
          .with(hosts, node_path) { false }
        expect(dummy_class).to receive(:get_node_data) \
          .with(hosts, File.dirname(node_path)) { false }
        expect(dummy_class).to receive(:get_node_data) \
          .with(hosts, node_path) { false }
        dbl = double(connected?: true,
                     closed?: true)
        expect(Zookeeper).to receive(:new) { dbl }
        expect(dbl).to receive(:create) \
          .with(path: ::File.dirname(node_path), data: '') \
          .exactly(1).times { { rc: 0 } }
        expect(Zookeeper).to receive(:new) { dbl }
        expect(dbl).to receive(:create) \
          .with(path: node_path, data: my_data) \
          .exactly(1).times { { rc: 0 } }
        expect(dummy_class.create_node(hosts, node_path,
                                       my_data)).to match(true)
      end

      it 'swallows exception and returns true' do
        # create_node tests for mkdir -p equiv
        expect(dummy_class).to receive(:get_node_data) \
          .with(hosts, node_path) { false }
        expect(dummy_class).to receive(:get_node_data) \
          .with(hosts, File.dirname(node_path)) { false }
        expect(dummy_class).to receive(:get_node_data) \
          .with(hosts, node_path) { false }
        # create nodes for mkdir -p equiv
        dbl = double(connected?: true,
                     create: { 'rc'.to_sym => 0 },
                     closed?: true)
        expect(Zookeeper).to receive(:new) { dbl }
        # actual test
        dbl = double(connected?: true,
                     create: { 'rc'.to_sym => 0 })
        expect(Zookeeper).to receive(:new) { dbl }
        expect(dbl).to receive(:closed?).and_raise(exception_str)
        expect(Chef::Log).to receive(:warn).with(exception_str)
        expect(dbl).to receive(:closed?).and_raise(exception_str)
        expect(Chef::Log).to receive(:warn).with(exception_str)
        expect(dummy_class.create_node(hosts, node_path,
                                       my_data)).to match(true)
      end

      it 'returns true if node created' do
        expect(dummy_class).to receive(:get_node_data) \
          .with(hosts, node_path) { true }
        dbl = double(connected?: true,
                     create: { 'rc'.to_sym => 0 },
                     closed?: true)
        expect(Zookeeper).to receive(:new) { dbl }
        expect(dummy_class.create_node(hosts, node_path,
                                       my_data)).to match(true)
      end
    end
  end

  describe '#lock_matches?' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end.new
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path/a_node' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:my_data) { 'my_data' }
      let(:exception_str) { 'Error from test - should be logged' }
      let(:dbl) { double }

      it 'returns true if lock matches' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:get).with(path: node_path).exactly(1) \
                                    .times { { data: my_data } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.lock_matches?(hosts, node_path,
                                         my_data)).to match(true)
      end

      it 'returns false if lock does not match' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:get).with(path: node_path).exactly(1) \
                                    .times { { data: 'random stuff' } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.lock_matches?(hosts, node_path,
                                         my_data)).to match(false)
      end

      it 'swallows an exception in Zk.close and returns true' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:get).with(path: node_path).exactly(1) \
                                    .times { { data: my_data } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times.and_raise(exception_str)
        expect(Chef::Log).to receive(:warn).with(exception_str)
        expect(dummy_class.lock_matches?(hosts, node_path,
                                         my_data)).to match(true)
      end
    end
  end

  describe '#release_lock' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end.new
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path/a_node' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:my_data) { 'my_data' }
      let(:exception_str) do
        'release_lock: node does not contain expected data ' \
          'not releasing the lock'
      end
      let(:dbl) { double }

      it 'returns true if lock matches' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dummy_class).to receive(:lock_matches?) \
          .with(hosts, node_path, my_data).exactly(1).times { true }
        expect(dbl).to receive(:delete) \
          .exactly(1).times \
          .with(path: node_path) { { 'rc'.to_sym => 0 } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.release_lock(hosts, node_path,
                                        my_data)).to match(true)
      end

      it 'returns false if lock does not match' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dummy_class).to receive(:lock_matches?) \
          .with(hosts, node_path, my_data).exactly(1).times { false }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect do
          dummy_class.release_lock(hosts,
                                   node_path,
                                   my_data)
        end.to raise_error(exception_str)
      end
    end
  end

  describe '#get_node_ctime' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end.new
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:stat) do
        double(exists:         true,
               ctime:          1_476_401_413_663,
               mtime:          1_476_401_413_663)
      end
      let(:dbl) { double }

      it 'returns data if node exists' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:stat) \
          .with(path: node_path) \
          .exactly(1).times { { rc: 0, stat: stat } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.get_node_ctime(hosts, node_path)) \
          .to match(Time.strptime('1476401413663', '%Q'))
      end

      it 'returns nil if node can not be read' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:stat) \
          .with(path: node_path) \
          .exactly(1).times { { rc: -101 } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.get_node_ctime(hosts, node_path)) \
          .to match(nil)
      end
    end
  end

  describe '#get_node_data' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end.new
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path/a_node' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:my_data) { 'my_data' }
      let(:exception_str) do
        "LockingResource: unable to connect to ZooKeeper quorum #{hosts}"
      end
      let(:dbl) { double }

      it 'returns data if node exists' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:get) \
          .with(path: node_path) \
          .exactly(1).times { { rc: 0, data: my_data } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.get_node_data(hosts, node_path)) \
          .to match(my_data)
      end

      it 'returns nil if node can not be read' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:get) \
          .with(path: node_path) \
          .exactly(1).times { { rc: -101 } }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect(dummy_class.get_node_data(hosts, node_path)) \
          .to match(nil)
      end
    end
  end

  describe '#run_zk_block' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end.new
    end

    context 'called without quorum_hosts' do
      it 'raises ArgumentError' do
        expect do
          dummy_class.run_zk_block(nil) { puts 'Failed if you see this' }
        end.to raise_error(ArgumentError)
      end
    end

    context 'called with reasonable parameters' do
      require 'zookeeper' # ugly but easier than mocking the require
      let(:node_path) { '/my_test_path/a_node' }
      let(:hosts) { 'localtest_no_host_to_connect:2181' }
      let(:my_data) { 'my_data' }
      let(:exception_str) do
        "LockingResource: unable to connect to ZooKeeper quorum #{hosts}"
      end
      let(:dbl) { double }

      it 'calls code in the block and returns value' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:closed?).exactly(1).times { true }
        expect(
          dummy_class.run_zk_block(hosts) { my_data }
        ).to eq(my_data)
      end

      it 'calls code in the block and returns nil if nothing returned' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dbl).to receive(:closed?).exactly(1).times { true }
        expect(
          dummy_class.run_zk_block(hosts) {}
        ).to eq(nil)
      end

      it 'raises if Zk.connect fails' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { false }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times
        expect do
          dummy_class.run_zk_block(hosts) { puts 'Fail if run' }
        end.to raise_error(exception_str)
      end

      it 'raises raises in the block and Zk.close raises first exception' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(Chef::Log).to receive(:warn).with('Exception in Block')
        expect(dbl).to receive(:nil?).exactly(1).times { false }
        expect(dbl).to receive(:closed?).exactly(1).times { false }
        expect(dbl).to receive(:close).exactly(1).times \
          .and_raise('Exception from close()')
        expect(Chef::Log).to receive(:warn).with('Exception from close()')
        expect do
          dummy_class.run_zk_block(hosts) do
            raise 'Exception in Block'
          end
        end.to raise_error(RuntimeError, 'Exception in Block')
      end

      it 'swallows an exception in Zk.closed? and returns block result value' do
        expect(Zookeeper).to receive(:new).with(hosts).exactly(1).times { dbl }
        expect(dbl).to receive(:connected?).exactly(1).times { true }
        expect(dummy_class).to receive(:lock_matches?) \
          .with(hosts, node_path, my_data).exactly(1).times { true }
        expect(dbl).to receive(:delete) \
          .exactly(1).times \
          .with(path: node_path) { { 'rc'.to_sym => 0 } }
        expect(dbl).to receive(:closed?) \
          .exactly(1).times \
          .and_raise(exception_str)
        expect(Chef::Log).to receive(:warn).with(exception_str)
        expect(dummy_class.release_lock(hosts, node_path,
                                        my_data)).to match(true)
      end
    end
  end

  describe '#process_start_time?' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end
    end

    context 'pgrep pid and reasonable ps and command' do
      # create an arbitrary list of plausible PIDs one per line
      let(:ps_output) { 'Tue Jul 12 14:38:34 2016' }
      let(:pgrep_output) { rand(1..2**15).to_s + "\n" }
      let(:test_command) { 'my command' }
      let(:error_string) { 'TEST: We got an error' }

      def return_stdout(arg)
        # return a PID for pgrep(1)
        return pgrep_output if arg.strip == %(pgrep -o -f "#{test_command}")
        # We must return a known date
        return "#{ps_output}\n" if arg.start_with?('ps')
        raise "Unexpected arg: |#{arg}|"
      end

      it 'raises under pgrep error' do
        expect(Mixlib::ShellOut).to receive(:new) do
          double(run_command: nil,
                 error!: '',
                 exitstatus: 0,
                 stdout: '',
                 stderr: error_string,
                 live_stream: '')
        end.exactly(1).times
        expect do
          dummy_class.new.process_start_time(full_cmd: true,
                                             command_string: test_command)
        end.to raise_error(error_string)
      end

      it 'returns the earliest time' do
        expect(Mixlib::ShellOut).to receive(:new) do |arg|
          double(run_command: nil,
                 error!: '',
                 exitstatus: 0,
                 stdout: return_stdout(arg),
                 stderr: '',
                 live_stream: '')
        end.exactly(2).times
        expect(dummy_class.new.process_start_time(
          full_cmd: true, command_string: test_command
        ).to_i).to eq(Time.parse(ps_output).to_i)
      end
    end
  end

  describe 'rerun functions' do
    let(:dummy_class) do
      Class.new do
        include LockingResource::Helper
      end
    end

    context 'test node has had reruns set' do
      let(:node) { Chef::Node.new }
      let(:mock_time) { Time.strptime('1476401413663', '%Q') }
      let(:path1_rerun_data) { { 'time' => mock_time - 10 * 60, 'fails' => 1 } }
      let(:path2_rerun_data) { { 'time' => mock_time - 30 * 60, 'fails' => 1 } }
      let(:path1) { 'cookbook::recipe::test_package' }
      let(:path2) { 'cookbook::recipe::test_bash' }
      before(:each) do
        node.normal['locking_resource']['failed_locks'] = {
          path1 => path1_rerun_data,
          path2 => path2_rerun_data
        }
      end

      it '#clear_rerun(path1) returns mock_time - 10 * 60' do
        expect(dummy_class.new.clear_rerun(node, path1)).to \
          match_array(path1_rerun_data)
      end

      it '#rerun_time?(path2) returns mock_time - 30 * 60' do
        expect(dummy_class.new.rerun_time?(node, path2)).to \
          eq(mock_time - 30 * 60)
      end

      it '#need_rerun(path1) returns mock_time - 10 * 60' do
        allow(Time).to receive(:now).and_return(mock_time)
        expect(dummy_class.new.need_rerun(node, path1)).to \
          match_array('time' => path1_rerun_data['time'],
                      'fails' => path1_rerun_data['fails'] + 1)
      end
    end

    context 'test node has not had a rerun set' do
      let(:node) { Chef::Node.new }
      before(:each) do
        node.normal['locking_resource']['failed_locks'] = {}
      end
      let(:path1) { 'cookbook::recipe::test_package' }
      let(:path2) { 'cookbook::recipe::test_bash' }
      let(:mock_time) { Time.strptime('1476401413663', '%Q') }
      let(:rerun_data) { { 'time' => mock_time, 'fails' => 1 } }

      it '#clear_rerun returns nil' do
        expect(dummy_class.new.clear_rerun(node, path1)).to eq(nil)
      end

      it '#rerun_time? returns nil' do
        expect(dummy_class.new.rerun_time?(node, path1)).to eq(nil)
      end

      it '#need_rerun returns current time' do
        allow(Time).to receive(:now).and_return(mock_time)
        expect(dummy_class.new.need_rerun(node, path1)).to \
          match_array(rerun_data)
      end
    end
  end
end
