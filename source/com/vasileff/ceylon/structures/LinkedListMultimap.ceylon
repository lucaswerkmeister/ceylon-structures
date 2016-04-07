import ceylon.collection {
    HashMap,
    MutableList,
    unlinked,
    MutableSet,
    HashSet
}
import ceylon.language {
    createMap=map
}
import com.vasileff.ceylon.structures.internal {
    eq,
    forward,
    Direction,
    SequentialList,
    SequentialMutableList
}

shared
class LinkedListMultimap<Key, Item>
        satisfies MutableListMultimap<Key, Item>
        given Key satisfies Object {

    class Node(shared Key key, shared variable Item item) {
        "The next node with any key"
        shared variable Node? next = null;

        "The next node with the same key"
        shared variable Node? nextSibling = null;

        "The previous node with any key"
        shared variable Node? previous = null;

        "The previous node with the same key"
        shared variable Node? previousSibling = null;

        shared Key->Item entry => key->item;
    }

    class KeyList(Node firstNode) {
        shared variable Node head = firstNode;

        shared variable Node tail = firstNode;

        firstNode.previousSibling = null;

        firstNode.nextSibling = null;

        shared variable Integer count = 1;
    }

    "The head for all keys"
    variable Node? head = null;

    "The tail for all keys"
    variable Node? tail = null;

    "A map from keys to nonempty linked lists of nodes"
    value backingMap = HashMap<Key, KeyList> { stability = unlinked; };

    "The total number of nodes."
    variable value nodeCount = 0;

    size => nodeCount;

    shared actual
    void clear() {
        head = null;
        tail = null;
        backingMap.clear();
        nodeCount = 0;
    }

    "Return the node at the specified index, or null if no node can be found at that
     index."
    Node? nodeFromFirst(variable Integer index) {
        variable Node? result = null;
        if (0 <= index < size) {
            if (index >= size / 2) {
                result = tail;
                while (++index < size, exists current = result) {
                    result = current.previous;
                }
            }
            else {
                result = head;
                while (index-- > 0, exists current = result) {
                    result = current.next;
                }
            }
        }
        return result;
    }

    "Return the node at the specified index for the given key, or null if no node can
     be found at that index."
    Node? nodeFromFirstForKey(Key key, variable Integer index) {
        variable Node? result = null;
        if (0 <= index, exists keyList = backingMap[key], index < keyList.count) {
            if (index >= keyList.count / 2) {
                result = keyList.tail;
                while (++index < keyList.count, exists current = result) {
                    result = current.previousSibling;
                }
            }
            else {
                result = keyList.head;
                while (index-- > 0, exists current = result) {
                    result = current.nextSibling;
                }
            }
        }
        return result;
    }

    "Returns an Iterable for nodes across all keys. Next is calculated one node in
     advance, so node removal is safe."
    {Node*} nodes(
            Direction direction = forward,
            Integer startIndex
                =   if (direction == forward)
                    then 0 else (size - 1))
            => object satisfies {Node*} {

        iterator() => object satisfies Iterator<Node> {
            variable value nextNode = nodeFromFirst(startIndex);
            shared actual Node | Finished next() {
                if (exists current = nextNode) {
                    nextNode = if (direction == forward)
                               then current.next
                               else current.previous;
                    return current;
                }
                return finished;
            }
        };
    };

    "Returns an Iterable for nodes with the specified [[key]]. Next is calculated one
     node in advance, so node removal is safe."
    {Node*} nodesForKey(
            Key key, Direction direction = forward,
            Integer startIndex
                =   if (direction == forward)
                    then 0 else (backingMap[key]?.count else -1))
            => object satisfies {Node*} {

        iterator() => object satisfies Iterator<Node> {
            variable value nextNode = nodeFromFirstForKey(key, startIndex);
            shared actual Node | Finished next() {
                if (exists current = nextNode) {
                    nextNode = if (direction == forward)
                               then current.nextSibling
                               else current.previousSibling;
                    return current;
                }
                return finished;
            }
        };
    };

    "Adds a new node for the specified key-value pair before the specified
     {@code nextSibling} element, or at the end of the list if {@code
     nextSibling} is null. Note: if {@code nextSibling} is specified, it MUST be
     for an node for the same {@code key}!"
    Node addNode(Key key, Item item, Node? nextSibling = null) {
        Node node = Node(key, item);

        if (!head exists) {
            // empty list
            head = tail = node;
            backingMap.put(node.key, KeyList(node));
        }
        else if (!exists nextSibling) {
            // non-empty list, add to tail
            assert (exists t = tail);
            t.next = node;
            node.previous = tail;
            tail = node;
            value keyList = backingMap[node.key];
            if (!exists keyList) {
                backingMap.put(node.key, KeyList(node));
            }
            else {
                keyList.count++;
                value keyTail = keyList.tail;
                keyTail.nextSibling = node;
                node.previousSibling = keyTail;
                keyList.tail = node;
            }
        }
        else {
            // non-empty list, insert before nextSibling

            "nextSibling was provided, so a keyList must exist."
            assert (exists keyList = backingMap[node.key]);
            keyList.count++;
            node.previous = nextSibling.previous;
            node.previousSibling = nextSibling.previousSibling;
            node.next = nextSibling;
            node.nextSibling = nextSibling;
            if (exists nps = nextSibling.previousSibling) {
                nps.nextSibling = node;
            }
            else { // nextSibling was key head
                keyList.head = node;
            }
            if (exists np =nextSibling.previous) {
                np.next = node;
            }
            else { // nextSibling was head
                head = node;
            }
            nextSibling.previous = node;
            nextSibling.previousSibling = node;
        }
        nodeCount++;
        return node;
    }

    "Remove the given node."
    void removeNode(Node node) {
        if (exists nodePrevious = node.previous) {
            nodePrevious.next = node.next;
        }
        else { // node was head
            head = node.next;
        }
        if (exists nodeNext = node.next) {
            nodeNext.previous = node.previous;
        }
        else { // node was tail
            tail = node.previous;
        }

        if (!node.previousSibling exists && !node.nextSibling exists) {
            // node was the only one of its key
            assert (exists keyList = backingMap.remove(node.key));
            keyList.count = 0;
        } else {
            assert (exists keyList = backingMap.get(node.key));
            keyList.count--;

            if (exists nodePreviousSibling = node.previousSibling) {
                nodePreviousSibling.nextSibling = node.nextSibling;
            } else {
                assert (exists nodeNextSibling = node.nextSibling);
                keyList.head = nodeNextSibling;
            }

            if (exists nodeNextSibling = node.nextSibling) {
                nodeNextSibling.previousSibling = node.previousSibling;
            } else {
                assert (exists nodePreviousSibling = node.previousSibling);
                keyList.tail = nodePreviousSibling;
            }
        }
        nodeCount--;
    }

    shared actual
    Boolean put(Key key, Item item) {
        addNode(key, item);
        return true;
    }

    shared
    new ({<Key->Item>*} entries = []) {
        for (key->item in entries) {
            put(key, item);
        }
    }

    shared actual
    Boolean defines(Key key)
        =>  backingMap.contains(key);

    shared actual
    Iterator<Key->Item> iterator()
        =>  nodes().map(Node.entry).iterator();

    shared actual
    MutableList<Item> get(Key key) => object extends Object()
            satisfies SequentialMutableList<Node, Item> {

        getElement(Node node) => node.item;

        insertNode(Item element, Node? location) => outer.addNode(key, element, location);

        nodeFromFirst(Integer index) => outer.nodeFromFirstForKey(key, index);

        nodeIterable(Direction direction, Integer startIndex)
            =>  nodesForKey(key, direction, startIndex);

        removeNode(Node node) => outer.removeNode(node);

        setElement(Node node, Item element) => node.item = element;

        size => backingMap[key]?.count else 0;
    };

    shared actual
    List<Item> items => object extends Object()
            satisfies SequentialList<Node, Item> {

        getElement(Node node) => node.item;

        nodeFromFirst(Integer index) => outer.nodeFromFirst(index);

        nodeIterable(Direction direction, Integer startIndex)
            =>  nodes(direction, startIndex);

        size => outer.size;
    };

    shared actual
    MutableSet<Key> keys => object satisfies MutableSet<Key> {

        clone() => HashSet { *this };

        contains(Object key) => backingMap.defines(key);

        iterator() => nodes().map(Node.key).distinct.iterator();

        size => backingMap.size;

        empty => backingMap.empty;

        add(Key element) => false;

        clear() => outer.clear();

        remove(Key element) => !outer.removeAll(element).empty;

        hash => (super of Set<Key>).hash;

        equals(Object that) => (super of Set<Key>).equals(that);
    };

    shared actual
    Map<Key, MutableList<Item>> asMap => object extends Object()
            satisfies Map<Key, MutableList<Item>> {

        // Note: we could return a MutableMap, but the semantics for put would be a
        // bit screwy.

        // clone the items too, since they are live views into the multimap
        clone() => createMap(this.map((entry) => entry.key -> entry.item.clone()));

        defines(Object key) => backingMap.contains(key);

        keys => outer.keys;

        size => backingMap.size;

        iterator() => keys.map((k) => k -> outer.get(k)).iterator();

        get(Object key) => if (defines(key), is Key key) then outer.get(key) else null;
    };

    shared actual
    Boolean remove(Key key, Item item) {
        for (node in nodesForKey(key)) {
            if (eq(node.item, item)) {
                removeNode(node);
                return true;
            }
        }
        return false;
    }

    shared actual
    List<Item> removeAll(Key key) {
        value items = get(key);
        value oldItems = items.sequence();
        items.clear();
        return oldItems;
    }

    shared actual
    List<Item> replaceItems(Key key, {Item*} items) {
        MutableList<Item> list = get(key);
        Item[] oldItems = list.sequence();
        list.clear();
        list.addAll(items);
        return oldItems;
    }

    clone() => LinkedListMultimap { *this };

    hash => (super of Multimap<Key, Item>).hash;

    equals(Object that) => (super of Multimap<Key, Item>).equals(that);
}
