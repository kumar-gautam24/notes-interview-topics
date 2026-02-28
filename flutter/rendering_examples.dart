import 'package:flutter/material.dart';

/// Example 1: StatelessWidget - Simple, no state
class SimpleCounterDisplay extends StatelessWidget {
  final int count;
  
  const SimpleCounterDisplay({
    super.key,
    required this.count,
  });
  
  @override
  Widget build(BuildContext context) {
    // This build() is called EVERY time parent rebuilds
    // Widget instance is recreated, but Element persists
    print('SimpleCounterDisplay.build() - count: $count');
    
    return Text(
      'Count: $count',
      style: const TextStyle(fontSize: 24),
    );
  }
}

/// Example 2: StatefulWidget - Has mutable state
class CounterWithState extends StatefulWidget {
  const CounterWithState({super.key});
  
  @override
  State<CounterWithState> createState() => _CounterWithStateState();
}

class _CounterWithStateState extends State<CounterWithState> {
  // This state is PRESERVED across rebuilds
  int _count = 0;
  
  @override
  void initState() {
    super.initState();
    print('🟢 initState() - State object created');
    // Called ONCE when State is first created
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print('🟡 didChangeDependencies() - Dependencies resolved');
    // Called after initState, and when InheritedWidgets change
  }
  
  @override
  Widget build(BuildContext context) {
    print('🔵 build() - Building widget tree, count: $_count');
    // Called every time setState() is called
    // Widget is recreated, but State object persists
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Count: $_count',
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            print('⚡ Button pressed - calling setState()');
            setState(() {
              _count++;
              // This triggers rebuild
              // State object (_CounterWithStateState) is NOT recreated
              // Only build() is called again
            });
          },
          child: const Text('Increment'),
        ),
      ],
    );
  }
  
  @override
  void didUpdateWidget(CounterWithState oldWidget) {
    super.didUpdateWidget(oldWidget);
    print('🟠 didUpdateWidget() - Widget config changed');
    // Called when widget configuration changes
    // But State object persists
  }
  
  @override
  void dispose() {
    print('🔴 dispose() - State permanently destroyed');
    // Called ONCE when widget is removed from tree permanently
    super.dispose();
  }
}

/// Example 3: Demonstrating widget comparison
class WidgetComparisonDemo extends StatefulWidget {
  const WidgetComparisonDemo({super.key});
  
  @override
  State<WidgetComparisonDemo> createState() => _WidgetComparisonDemoState();
}

class _WidgetComparisonDemoState extends State<WidgetComparisonDemo> {
  int _counter = 0;
  bool _useKey = true;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widget Comparison')),
      body: Column(
        children: [
          // Example showing how keys affect element reuse
          if (_useKey)
            CounterDisplay(
              key: const ValueKey('counter'),  // Same key always
              count: _counter,
            )
          else
            CounterDisplay(
              key: ValueKey('counter-$_counter'),  // Different key each time
              count: _counter,
            ),
          
          const SizedBox(height: 20),
          
          ElevatedButton(
            onPressed: () {
              setState(() {
                _counter++;
              });
            },
            child: const Text('Increment'),
          ),
          
          ElevatedButton(
            onPressed: () {
              setState(() {
                _useKey = !_useKey;
              });
            },
            child: Text(_useKey ? 'Using Same Key' : 'Using Different Keys'),
          ),
        ],
      ),
    );
  }
}

class CounterDisplay extends StatefulWidget {
  final int count;
  
  const CounterDisplay({
    super.key,
    required this.count,
  });
  
  @override
  State<CounterDisplay> createState() => _CounterDisplayState();
}

class _CounterDisplayState extends State<CounterDisplay> {
  late int _internalCount;
  
  @override
  void initState() {
    super.initState();
    _internalCount = widget.count;
    print('CounterDisplay.initState() - count: ${widget.count}');
  }
  
  @override
  void didUpdateWidget(CounterDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    print('CounterDisplay.didUpdateWidget() - old: ${oldWidget.count}, new: ${widget.count}');
    _internalCount = widget.count;
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue),
      ),
      child: Column(
        children: [
          Text('Widget count: ${widget.count}'),
          Text('Internal count: $_internalCount'),
          Text('State hash: ${hashCode}'),
        ],
      ),
    );
  }
}

/// Example 4: Demonstrating rebuild scope
class RebuildScopeDemo extends StatefulWidget {
  const RebuildScopeDemo({super.key});
  
  @override
  State<RebuildScopeDemo> createState() => _RebuildScopeDemoState();
}

class _RebuildScopeDemoState extends State<RebuildScopeDemo> {
  int _counter = 0;
  
  @override
  Widget build(BuildContext context) {
    print('RebuildScopeDemo.build() - counter: $_counter');
    
    return Scaffold(
      appBar: AppBar(title: const Text('Rebuild Scope')),
      body: Column(
        children: [
          // This rebuilds every time
          _ExpensiveWidget(title: 'Rebuilds Always'),
          
          // This also rebuilds (parent rebuilds)
          SimpleCounterDisplay(count: _counter),
          
          const SizedBox(height: 20),
          
          // Isolated rebuild - only this rebuilds
          _IsolatedCounter(),
          
          const SizedBox(height: 20),
          
          ElevatedButton(
            onPressed: () {
              setState(() {
                _counter++;
              });
            },
            child: const Text('Increment (rebuilds parent)'),
          ),
        ],
      ),
    );
  }
}

class _ExpensiveWidget extends StatelessWidget {
  final String title;
  
  const _ExpensiveWidget({required this.title});
  
  @override
  Widget build(BuildContext context) {
    print('_ExpensiveWidget.build() - $title');
    // Simulate expensive operation
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.grey[300],
      child: Text(title),
    );
  }
}

class _IsolatedCounter extends StatefulWidget {
  const _IsolatedCounter();
  
  @override
  State<_IsolatedCounter> createState() => _IsolatedCounterState();
}

class _IsolatedCounterState extends State<_IsolatedCounter> {
  int _count = 0;
  
  @override
  Widget build(BuildContext context) {
    print('_IsolatedCounter.build() - count: $_count');
    // This only rebuilds when its own setState is called
    // Parent rebuilds don't affect it (if parent is StatelessWidget)
    
    return Column(
      children: [
        Text('Isolated Count: $_count'),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _count++;
            });
          },
          child: const Text('Increment (isolated)'),
        ),
      ],
    );
  }
}

/// Example 5: Demonstrating const optimization
class ConstOptimizationDemo extends StatelessWidget {
  const ConstOptimizationDemo({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Const Optimization')),
      body: Column(
        children: [
          // Without const - new instances every build
          _NonConstWidget(),
          
          const SizedBox(height: 20),
          
          // With const - reused instances
          const _ConstWidget(),
          
          const SizedBox(height: 20),
          
          // Mixed
          Column(
            children: [
              const Text('Static text'),  // Reused
              Text('Dynamic: ${DateTime.now()}'),  // New every build
            ],
          ),
        ],
      ),
    );
  }
}

class _NonConstWidget extends StatelessWidget {
  _NonConstWidget() : super(key: null);
  
  @override
  Widget build(BuildContext context) {
    print('_NonConstWidget.build() - NEW instance: ${hashCode}');
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.red[100],
      child: const Text('Non-const widget (recreated every build)'),
    );
  }
}

class _ConstWidget extends StatelessWidget {
  const _ConstWidget();
  
  @override
  Widget build(BuildContext context) {
    print('_ConstWidget.build() - REUSED instance: ${hashCode}');
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.green[100],
      child: const Text('Const widget (reused across builds)'),
    );
  }
}

/// Example 6: Complete lifecycle demonstration
class LifecycleDemo extends StatefulWidget {
  const LifecycleDemo({super.key});
  
  @override
  State<LifecycleDemo> createState() => _LifecycleDemoState();
}

class _LifecycleDemoState extends State<LifecycleDemo> {
  int _step = 0;
  
  @override
  void initState() {
    super.initState();
    _log('1️⃣ initState() - State object created');
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _log('2️⃣ didChangeDependencies() - Dependencies resolved');
  }
  
  @override
  Widget build(BuildContext context) {
    _log('3️⃣ build() - Building widget tree (step: $_step)');
    
    return Scaffold(
      appBar: AppBar(title: const Text('Lifecycle Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Step: $_step', style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _step++;
                  _log('⚡ setState() called - step: $_step');
                });
              },
              child: const Text('Next Step'),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void didUpdateWidget(LifecycleDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _log('4️⃣ didUpdateWidget() - Widget config changed');
  }
  
  @override
  void deactivate() {
    _log('5️⃣ deactivate() - Widget removed from tree');
    super.deactivate();
  }
  
  @override
  void dispose() {
    _log('6️⃣ dispose() - State permanently destroyed');
    super.dispose();
  }
  
  void _log(String message) {
    print('📋 LifecycleDemo: $message');
  }
}

/// Main demo screen combining all examples
class RenderingExamplesScreen extends StatelessWidget {
  const RenderingExamplesScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Rendering Examples')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildExampleCard(
            context,
            title: '1. StatelessWidget',
            description: 'Simple widget with no state',
            widget: const SimpleCounterDisplay(count: 42),
          ),
          _buildExampleCard(
            context,
            title: '2. StatefulWidget',
            description: 'Widget with mutable state',
            widget: const CounterWithState(),
          ),
          _buildExampleCard(
            context,
            title: '3. Widget Comparison',
            description: 'How keys affect element reuse',
            widget: const WidgetComparisonDemo(),
            fullScreen: true,
          ),
          _buildExampleCard(
            context,
            title: '4. Rebuild Scope',
            description: 'Understanding what rebuilds',
            widget: const RebuildScopeDemo(),
            fullScreen: true,
          ),
          _buildExampleCard(
            context,
            title: '5. Const Optimization',
            description: 'Performance with const widgets',
            widget: const ConstOptimizationDemo(),
          ),
          _buildExampleCard(
            context,
            title: '6. Complete Lifecycle',
            description: 'Full StatefulWidget lifecycle',
            widget: const LifecycleDemo(),
            fullScreen: true,
          ),
        ],
      ),
    );
  }
  
  Widget _buildExampleCard(
    BuildContext context, {
    required String title,
    required String description,
    required Widget widget,
    bool fullScreen = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (fullScreen)
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => widget),
                  );
                },
                child: const Text('Open Demo'),
              )
            else
              widget,
          ],
        ),
      ),
    );
  }
}

